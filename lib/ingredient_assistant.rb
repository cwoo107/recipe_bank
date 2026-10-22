require "httparty"

# The AI behind ingredient handling — the recipe importer and
# IngredientEnrichmentJob: estimating nutrition and prices, sorting
# ingredients into families (Ingredient::FAMILIES), and matching imported
# ingredients to ones the household already has.
#
# Two providers, picked by INGREDIENT_AI:
#   ollama (the default) — a self-hosted Ollama at OLLAMA_URL (OLLAMA_MODEL,
#     llama2 by default), asked for JSON. What runs on Railway today.
#   claude — Claude Haiku through the official SDK, with a JSON schema per
#     answer (structured outputs), so a reply is always the shape asked for.
#     Needs ANTHROPIC_API_KEY. For the move off Railway.
#
# Every method has an offline fallback — family guesses from the name,
# rough nutrition by family, "create it" for matching — used whenever the
# AI can't answer: Ollama unreachable, no ANTHROPIC_API_KEY, an API error,
# a refused request (Haiku has no server-side refusal fallback) or a reply
# cut short. Imports never fail because the AI did.
class IngredientAssistant
  PROVIDERS = %w[ollama claude].freeze

  MODEL = "claude-haiku-5-5"

  # Lookup-style work — low effort keeps it quick and cheap. Haiku thinks
  # by default, and that counts toward max_tokens, so there's headroom.
  EFFORT     = :low
  MAX_TOKENS = 16_000

  NUTRITION_SCHEMA = {
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name:          { type: "string" },
            serving_size:  { type: "number" },
            serving_unit:  { type: "string", enum: %w[cup tbsp tsp oz g piece] },
            calories:      { type: "number" },
            protein:       { type: "number" },
            total_fat:     { type: "number" },
            total_carb:    { type: "number" },
            unit_price:    { type: "number" },
            unit_servings: { type: "number" }
          },
          required: %w[name serving_size serving_unit calories protein total_fat total_carb unit_price unit_servings],
          additionalProperties: false
        }
      }
    },
    required: [ "items" ],
    additionalProperties: false
  }.freeze

  def initialize(provider: ENV["INGREDIENT_AI"], client: nil, ollama_model: ENV["OLLAMA_MODEL"])
    @provider     = PROVIDERS.include?(provider.to_s) ? provider.to_s : "ollama"
    @client       = client
    @ollama_model = ollama_model.presence || "llama2"
  end

  attr_reader :provider

  def estimate_nutrition_facts(ingredients)
    Rails.logger.info "=== ESTIMATING NUTRITION FOR #{ingredients.length} INGREDIENTS ==="

    items = ask(build_nutrition_prompt(ingredients), NUTRITION_SCHEMA, task: "nutrition", timeout: 180)
    return items if items.present?

    ingredients.map { |ing| fallback_nutrition_estimate(ing[:name], ing[:family]) }
  end

  def classify_ingredient_families(ingredients)
    Rails.logger.info "=== CLASSIFYING FAMILIES FOR #{ingredients.length} INGREDIENTS ==="

    items = ask(build_family_classification_prompt(ingredients), family_schema, task: "classification", timeout: 120)
    return items if items.present?

    ingredients.map { |ing| { "name" => ing[:name], "family" => guess_family_programmatically(ing[:name]) } }
  end

  # unmatched_with_candidates: array of { ingredient: <parsed ingredient hash>,
  # candidates: [<existing ingredient name>, ...] }, one candidate shortlist
  # per ingredient (see IngredientMatcher#candidates_for) rather than a single
  # sample shared across all of them.
  def resolve_ingredients(unmatched_with_candidates)
    Rails.logger.info "=== RESOLVING #{unmatched_with_candidates.length} UNMATCHED INGREDIENTS ==="

    items = ask(build_prompt(unmatched_with_candidates), resolution_schema, task: "resolution", timeout: 120)
    return items if items.present?

    fallback_resolution(unmatched_with_candidates)
  end

  private

  # The answer's items (string keys), or nil when there's no answer to use —
  # the caller falls back.
  def ask(prompt, schema, task:, timeout:)
    provider == "claude" ? ask_claude(prompt, schema, task:) : ask_ollama(prompt, task:, timeout:)
  end

  # Ollama's /api/generate in JSON mode, as the app has always used it. Its
  # JSON can be the list itself or wrapped in an object.
  def ask_ollama(prompt, task:, timeout:)
    response = HTTParty.post(
      "#{ENV.fetch('OLLAMA_URL', 'http://localhost:11434')}/api/generate",
      body: { model: @ollama_model, prompt:, stream: false, format: "json" }.to_json,
      headers: { "Content-Type" => "application/json" },
      timeout:
    )
    Rails.logger.info "Ollama #{task} response status: #{response.code}"

    unless response.success?
      Rails.logger.error "Ollama #{task} API error: #{response.code}; using fallback"
      return nil
    end

    text = JSON.parse(response.body)["response"].to_s
    data = JSON.parse(text.gsub(/```json\n?|\n?```/, "").strip)
    items = data.is_a?(Hash) ? (data["items"] || data.values.find { |value| value.is_a?(Array) }) : data
    items.is_a?(Array) && items.any? ? items : nil
  rescue StandardError => e
    Rails.logger.error "Ollama #{task} error: #{e.class} - #{e.message}; using fallback"
    nil
  end

  # Claude Haiku, with `schema` as the answer's shape ({ "items": [...] }).
  def ask_claude(prompt, schema, task:)
    return nil unless client

    response = client.messages.create(
      model: MODEL,
      max_tokens: MAX_TOKENS,
      output_config: { effort: EFFORT, format_: { type: :json_schema, schema: } },
      messages: [ { role: "user", content: prompt } ]
    )

    unless response.stop_reason == :end_turn
      Rails.logger.warn "Claude #{task}: no usable answer (stop_reason #{response.stop_reason}#{" — #{response.stop_details&.category}" if response.stop_reason == :refusal}); using fallback"
      return nil
    end

    # The answer is the text block — Haiku can put thinking blocks first.
    text = response.content.find { |block| block.type == :text }&.text
    JSON.parse(text.to_s).fetch("items")
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::APIConnectionError => e
    Rails.logger.warn "Claude #{task} unavailable (#{e.class}): #{e.message}; using fallback"
    nil
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error "Claude #{task} API error #{e.status}: #{e.message}; using fallback"
    nil
  rescue JSON::ParserError, KeyError => e
    Rails.logger.error "Claude #{task}: unreadable answer (#{e.class}: #{e.message}); using fallback"
    nil
  end

  # How each prompt asks for its answer: Ollama with its original wording
  # (a bare JSON array); Claude for the items array its schema describes.
  def output_instruction
    if provider == "claude"
      "Answer with an items array — one entry per ingredient, in the order listed — each shaped like:"
    else
      "Respond with ONLY valid JSON array (no markdown, no explanation):"
    end
  end

  # Nil without an API key, so the fallbacks run (local development, tests).
  def client
    return @client if @client
    return nil if ENV["ANTHROPIC_API_KEY"].blank?

    @client = Anthropic::Client.new(timeout: 120)
  end

  def family_schema
    {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              name:   { type: "string" },
              family: { type: "string", enum: Ingredient::FAMILIES.keys }
            },
            required: %w[name family],
            additionalProperties: false
          }
        }
      },
      required: [ "items" ],
      additionalProperties: false
    }
  end

  def resolution_schema
    nullable_string = { anyOf: [ { type: "string" }, { type: "null" } ] }
    {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              original:   { type: "string" },
              action:     { type: "string", enum: %w[match create] },
              match_name: nullable_string,
              name:       { type: "string" },
              quantity:   { type: "number" },
              unit:       nullable_string,
              family:     { type: "string", enum: Ingredient::FAMILIES.keys }
            },
            required: %w[original action match_name name quantity unit family],
            additionalProperties: false
          }
        }
      },
      required: [ "items" ],
      additionalProperties: false
    }
  end


  def build_nutrition_prompt(ingredients)
    <<~PROMPT
      You are estimating nutrition facts and pricing for grocery ingredients.
      
      For each ingredient, provide:
      1. Nutrition facts per typical serving
      2. Estimated retail price per unit
      3. Number of servings per typical purchase unit
      
      Ingredients:
      #{ingredients.map { |i| "- #{i[:name]} (family: #{i[:family]})" }.join("\n")}
      
      Guidelines:
      - Serving sizes should be realistic (e.g., 1 cup, 100g, 1 tablespoon)
      - Prices should be typical US grocery store prices in dollars
      - Unit servings = how many recipe servings you get from one purchase unit
        Example: 1 lb chicken breast = about 4 servings
        Example: 1 bottle olive oil (16 oz) = about 32 tablespoon servings
      
      #{output_instruction}
      [
        {
          "name": "ingredient name",
          "serving_size": number (amount per serving),
          "serving_unit": "cup|tbsp|tsp|oz|g|piece",
          "calories": number (per serving),
          "protein": number (grams per serving),
          "total_fat": number (grams per serving),
          "total_carb": number (grams per serving),
          "unit_price": number (dollars for typical purchase unit),
          "unit_servings": number (servings per purchase unit)
        }
      ]
      
      Examples:
      - Chicken breast: serving_size=4, serving_unit="oz", calories=165, protein=31, fat=3.6, carb=0, unit_price=8.99, unit_servings=4
      - Olive oil: serving_size=1, serving_unit="tbsp", calories=120, protein=0, fat=14, carb=0, unit_price=12.99, unit_servings=32
      - Salt: serving_size=1, serving_unit="tsp", calories=0, protein=0, fat=0, carb=0, unit_price=2.99, unit_servings=100
    PROMPT
  end

  def build_family_classification_prompt(ingredients)
    <<~PROMPT
      You are classifying grocery ingredients into families for meal planning.
      
      Ingredients to classify:
      #{ingredients.map { |i| "- #{i[:name]}" }.join("\n")}
      
      Available families:
      #{family_descriptions}
      
      Rules:
      - Salt, pepper, and all dried seasonings = spices
      - Fresh herbs (basil, cilantro, parsley) = produce
      - Butter and cream can be either dairy or fat, choose dairy
      - Stock/broth and canned beans = canned; dried beans and lentils = protein
      - Frozen versions of anything (frozen peas, frozen chicken) = frozen
      - Use grocery only when nothing else fits
      
      #{output_instruction}
      [
        {
          "name": "ingredient name",
          "family": "one of: #{Ingredient::FAMILIES.keys.join(', ')}"
        }
      ]
    PROMPT
  end

  def build_prompt(unmatched_with_candidates)
    items = unmatched_with_candidates.map do |entry|
      candidates_text = entry[:candidates].any? ? entry[:candidates].join(', ') : '(no similar ingredients found)'
      "- Ingredient: \"#{entry[:ingredient][:original]}\"\n  Candidates: #{candidates_text}"
    end.join("\n")

    <<~PROMPT
      You are helping match recipe ingredients to a database and classify them into families.

      For each ingredient below, decide whether it is the same as one of ITS OWN
      candidate existing ingredients, or should be created as new. Only return
      "match" with a match_name that is exactly one of that ingredient's own
      listed candidates — never invent a match_name that isn't listed there.

      #{items}

      Available families:
      #{family_descriptions}

      #{output_instruction}
      [
        {
          "original": "ingredient text from recipe",
          "action": "match" or "create",
          "match_name": "one of that ingredient's candidates if match, else null",
          "name": "clean ingredient name",
          "quantity": number,
          "unit": "standardized unit or null",
          "family": "one of: #{Ingredient::FAMILIES.keys.join(', ')}"
        }
      ]
    PROMPT
  end

  def fallback_resolution(unmatched_with_candidates)
    unmatched_with_candidates.map do |entry|
      ing = entry[:ingredient]
      {
        'original' => ing[:original],
        'action' => 'create',
        'match_id' => nil,
        'name' => ing[:name],
        'quantity' => ing[:quantity],
        'unit' => ing[:unit],
        'family' => guess_family_programmatically(ing[:name])
      }
    end
  end

  def fallback_nutrition_estimate(name, family)
    # Provide rough estimates based on family
    base = case family
           when 'protein'
             { calories: 165, protein: 25, total_fat: 5, total_carb: 0, serving_size: 4, serving_unit: 'oz', unit_price: 8.99, unit_servings: 4 }
           when 'produce'
             { calories: 25, protein: 1, total_fat: 0, total_carb: 6, serving_size: 1, serving_unit: 'cup', unit_price: 3.99, unit_servings: 4 }
           when 'dairy'
             { calories: 100, protein: 8, total_fat: 5, total_carb: 12, serving_size: 1, serving_unit: 'cup', unit_price: 4.99, unit_servings: 8 }
           when 'grain'
             { calories: 200, protein: 7, total_fat: 2, total_carb: 40, serving_size: 1, serving_unit: 'cup', unit_price: 3.99, unit_servings: 8 }
           when 'fat'
             { calories: 120, protein: 0, total_fat: 14, total_carb: 0, serving_size: 1, serving_unit: 'tbsp', unit_price: 9.99, unit_servings: 32 }
           when 'spices'
             { calories: 0, protein: 0, total_fat: 0, total_carb: 0, serving_size: 1, serving_unit: 'tsp', unit_price: 4.99, unit_servings: 50 }
           else
             { calories: 50, protein: 1, total_fat: 1, total_carb: 10, serving_size: 1, serving_unit: 'cup', unit_price: 3.99, unit_servings: 4 }
           end

    Rails.logger.info "Fallback nutrition for #{name}: #{base.inspect}"
    base.merge(name: name)
  end

  # The prompt's "Available families" list, from Ingredient::FAMILIES.
  def family_descriptions
    Ingredient::FAMILIES.map { |key, config| "- #{key}: #{config[:description]}" }.join("\n      ")
  end

  def guess_family_programmatically(name)
    name = name.downcase

    # Frozen (check first - "frozen peas" is frozen, not produce)
    return 'frozen' if name.match?(/\b(frozen|ice cream|popsicle|sorbet)\b/)

    # Canned & jarred (before protein/produce - "canned black beans", "chicken broth")
    if name.match?(/\b(canned|jarred|stock|broth|bouillon|tomato paste|tomato sauce|crushed tomatoes|diced tomatoes|coconut milk|evaporated milk|condensed milk)\b/)
      return 'canned'
    end

    # Condiments (before produce - "chili sauce", "apple cider vinegar")
    if name.match?(/\b(sauce|ketchup|mustard|mayo|mayonnaise|vinegar|dressing|salsa|relish|sriracha|soy sauce|tamari|worcestershire|honey|maple syrup|syrup|jam|jelly|preserves|pesto|hummus|aioli|chutney)\b/)
      return 'condiments'
    end

    # Baking (before spices - "vanilla extract")
    if name.match?(/\b(sugar|baking soda|baking powder|yeast|cornstarch|cocoa|chocolate chips?|chocolate|extract|gelatin|sprinkles|molasses)\b/)
      return 'baking'
    end

    # Nuts & seeds
    if name.match?(/\b(almonds?|walnuts?|pecans?|cashews?|pistachios?|peanuts?|hazelnuts?|macadamia|pine nuts?|nuts?|seeds?|chia|flax|flaxseed|peanut butter|almond butter|raisins?|dried fruit)\b/)
      return 'nuts'
    end

    # Beverages
    return 'beverages' if name.match?(/\b(coffee|espresso|tea|juice|soda|wine|beer|sparkling water|kombucha)\b/)

    # Protein
    if name.match?(/\b(chicken|beef|pork|turkey|duck|lamb|veal|venison|fish|salmon|tuna|cod|tilapia|trout|shrimp|prawn|lobster|crab|scallop|clam|mussel|oyster|egg|tofu|tempeh|seitan|beans?|lentils?|chickpeas?|peas?|meat|breast|thigh|drumstick|wing|ground|steak|chop|roast|bacon|sausage|ham)\b/)
      return 'protein'
    end

    # Spices (check before produce to catch dried herbs)
    if name.match?(/\b(salt|pepper|paprika|cumin|coriander|cinnamon|nutmeg|ginger powder|garlic powder|onion powder|cayenne|chili powder|chili flake|red pepper flake|oregano|thyme|rosemary|sage|bay leaf|bay|cardamom|clove|turmeric|curry|seasoning|spice|vanilla extract|almond extract|extract)\b/)
      return 'spices'
    end

    # Dairy
    if name.match?(/\b(milk|cheese|yogurt|cream|butter|sour cream|cottage cheese|ricotta|mozzarella|cheddar|parmesan|swiss|gouda|brie|feta|cream cheese|half and half|buttermilk|whey|ghee)\b/)
      return 'dairy'
    end

    # Grain
    if name.match?(/\b(bread|pasta|rice|flour|oat|cereal|tortilla|quinoa|couscous|noodle|spaghetti|macaroni|penne|fettuccine|linguine|cracker|bagel|roll|bun|pita|baguette|cornmeal|polenta|bulgur|barley|wheat|rye)\b/)
      return 'grain'
    end

    # Fat/Oil
    if name.match?(/\b(oil|olive oil|vegetable oil|canola oil|coconut oil|avocado oil|sesame oil|peanut oil|sunflower oil|grapeseed oil|lard|shortening|cooking spray)\b/)
      return 'fat'
    end

    # Produce (last - most general, includes fresh herbs)
    if name.match?(/\b(tomato|onion|garlic|potato|carrot|celery|pepper|bell pepper|lettuce|spinach|kale|broccoli|cauliflower|cucumber|zucchini|squash|eggplant|mushroom|asparagus|green bean|corn|pea|apple|banana|orange|lemon|lime|berry|strawberry|blueberry|raspberry|grape|melon|peach|pear|plum|cherry|mango|pineapple|avocado|basil|cilantro|parsley|mint|dill|tarragon|chive|scallion|green onion|leek|shallot|herb|fruit|vegetable|produce)\b/)
      return 'produce'
    end

    # Default to the catch-all if unclear
    'grocery'
  end
end