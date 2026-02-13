require 'httparty'

class OllamaAssistant
  include HTTParty
  base_uri 'http://localhost:11434'

  def initialize(model: 'llama2')
    @model = model
  end

  def estimate_nutrition_facts(ingredients)
    Rails.logger.info "=== ESTIMATING NUTRITION FOR #{ingredients.length} INGREDIENTS ==="
    ingredients.each { |i| Rails.logger.info "  - #{i[:name]} (#{i[:family]})" }

    prompt = build_nutrition_prompt(ingredients)

    begin
      response = self.class.post('/api/generate', {
        body: {
          model: @model,
          prompt: prompt,
          stream: false,
          format: 'json'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 180
      })

      Rails.logger.info "Ollama nutrition response status: #{response.code}"

      if response.success?
        result = JSON.parse(response.body)
        Rails.logger.info "Raw Ollama response length: #{result['response']&.length || 0} characters"

        parsed = parse_response(result['response'])
        Rails.logger.info "Parsed #{parsed.length} nutrition estimates"

        if parsed.empty? || !parsed.is_a?(Array)
          Rails.logger.warn "Ollama returned invalid nutrition data, using fallback"
          return ingredients.map { |ing| fallback_nutrition_estimate(ing[:name], ing[:family]) }
        end

        return parsed
      else
        Rails.logger.error "Ollama API error: #{response.code}"
        raise "Ollama API error: #{response.code}"
      end
    rescue => e
      Rails.logger.error("Ollama nutrition error: #{e.class} - #{e.message}")
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Return properly formatted fallback
      return ingredients.map do |ing|
        fallback_nutrition_estimate(ing[:name], ing[:family])
      end
    end
  end

  def classify_ingredient_families(ingredients)
    Rails.logger.info "=== CLASSIFYING FAMILIES FOR #{ingredients.length} INGREDIENTS ==="

    prompt = build_family_classification_prompt(ingredients)

    begin
      response = self.class.post('/api/generate', {
        body: {
          model: @model,
          prompt: prompt,
          stream: false,
          format: 'json'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 120
      })

      Rails.logger.info "Ollama classification response status: #{response.code}"

      if response.success?
        result = JSON.parse(response.body)
        parsed = parse_response(result['response'])

        Rails.logger.info "Parsed #{parsed.length} family classifications"

        if parsed.empty? || !parsed.is_a?(Array)
          Rails.logger.warn "Ollama returned invalid classification data, using fallback"
          return ingredients.map do |ing|
            {
              'name' => ing[:name],
              'family' => guess_family_programmatically(ing[:name])
            }
          end
        end

        return parsed
      else
        Rails.logger.error "Ollama API error: #{response.code}"
        raise "Ollama API error: #{response.code}"
      end
    rescue => e
      Rails.logger.error("Ollama classification error: #{e.class} - #{e.message}")
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Return properly formatted fallback
      return ingredients.map do |ing|
        {
          'name' => ing[:name],
          'family' => guess_family_programmatically(ing[:name])
        }
      end
    end
  end

  def resolve_ingredients(unmatched_ingredients, existing_ingredients_sample)
    Rails.logger.info "=== RESOLVING #{unmatched_ingredients.length} UNMATCHED INGREDIENTS ==="

    prompt = build_prompt(unmatched_ingredients, existing_ingredients_sample)

    begin
      response = self.class.post('/api/generate', {
        body: {
          model: @model,
          prompt: prompt,
          stream: false,
          format: 'json'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 120
      })

      Rails.logger.info "Ollama resolution response status: #{response.code}"

      if response.success?
        result = JSON.parse(response.body)
        parsed = parse_response(result['response'])

        if parsed.empty? || !parsed.is_a?(Array)
          Rails.logger.warn "Ollama returned invalid resolution data, using fallback"
          return unmatched_ingredients.map do |ing|
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

        return parsed
      else
        raise "Ollama API error: #{response.code}"
      end
    rescue => e
      Rails.logger.error("Ollama resolution error: #{e.class} - #{e.message}")

      return unmatched_ingredients.map do |ing|
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
  end

  private

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
      
      Respond with ONLY valid JSON array (no markdown, no explanation):
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
      - protein: meat, poultry, fish, eggs, tofu, beans, legumes
      - produce: fruits, vegetables, fresh herbs
      - dairy: milk, cheese, yogurt, butter, cream
      - grain: bread, pasta, rice, flour, oats, cereal
      - fat: cooking oils, butter, lard, shortening
      - spices: dried herbs, spices, seasonings, salt, pepper
      
      Rules:
      - Salt, pepper, and all dried seasonings = spices
      - Fresh herbs (basil, cilantro, parsley) = produce
      - Butter and cream can be either dairy or fat, choose dairy
      - Stock/broth = protein
      
      Respond with ONLY valid JSON array (no markdown, no explanation):
      [
        {
          "name": "ingredient name",
          "family": "one of: protein, produce, dairy, grain, fat, spices"
        }
      ]
    PROMPT
  end

  def build_prompt(unmatched, existing_sample)
    <<~PROMPT
      You are helping match recipe ingredients to a database and classify them into families.
      
      Unmatched ingredients from recipe:
      #{unmatched.map { |i| "- #{i[:original]}" }.join("\n")}
      
      Sample of existing ingredients in database:
      #{existing_sample.join(", ")}
      
      Available families:
      - protein: meat, poultry, fish, eggs, tofu, beans, legumes
      - produce: fruits, vegetables, fresh herbs
      - dairy: milk, cheese, yogurt, butter, cream
      - grain: bread, pasta, rice, flour, oats, cereal
      - fat: cooking oils, butter, lard, shortening
      - spices: dried herbs, spices, seasonings, salt, pepper
      
      For each unmatched ingredient, decide if it should match an existing ingredient or be created as new.
      Also assign the appropriate family.
      
      Respond with ONLY valid JSON array (no markdown, no explanation):
      [
        {
          "original": "ingredient text from recipe",
          "action": "match" or "create",
          "match_name": "name of existing ingredient if match, else null",
          "name": "clean ingredient name",
          "quantity": number,
          "unit": "standardized unit or null",
          "family": "one of: protein, produce, dairy, grain, fat, spices"
        }
      ]
    PROMPT
  end

  def parse_response(response_text)
    # Remove markdown code blocks if present
    cleaned = response_text.gsub(/```json\n?|\n?```/, '').strip

    JSON.parse(cleaned)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse Ollama response: #{e.message}")
    Rails.logger.error("Response text: #{response_text&.truncate(500)}")
    []
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

  def guess_family_programmatically(name)
    name = name.downcase

    # Protein (check first - most specific)
    if name.match?(/\b(chicken|beef|pork|turkey|duck|lamb|veal|venison|fish|salmon|tuna|cod|tilapia|trout|shrimp|prawn|lobster|crab|scallop|clam|mussel|oyster|egg|tofu|tempeh|seitan|bean|lentil|chickpea|pea|stock|broth|meat|breast|thigh|drumstick|wing|ground|steak|chop|roast|bacon|sausage|ham)\b/)
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

    # Default to produce if unclear
    'produce'
  end
end