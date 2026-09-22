class RecipeImporter
  def initialize(import_job)
    @job = import_job
  end

  def perform
    begin
      # Step 1: Fetch HTML
      @job.update_progress(:fetching_html)
      sleep 0.5
      scraped_data = RecipeScraper.new(@job.url).scrape

      # Log what we scraped for debugging
      Rails.logger.info "=== SCRAPED DATA ==="
      Rails.logger.info "Title: #{scraped_data[:title]}"
      Rails.logger.info "Description: #{scraped_data[:description]&.truncate(100)}"
      Rails.logger.info "Servings: #{scraped_data[:servings]}"
      Rails.logger.info "Ingredients (#{scraped_data[:ingredients]&.length || 0}): #{scraped_data[:ingredients]&.first(3)&.join(', ')}"
      Rails.logger.info "Steps (#{scraped_data[:steps]&.length || 0}): #{scraped_data[:steps]&.first&.truncate(50)}"

      @job.update!(scraped_data: scraped_data)

      # Step 2: Parse recipe structure
      @job.update_progress(:parsing_recipe)
      sleep 0.5
      validate_scraped_data(scraped_data)

      # Step 3: Match ingredients, then hand over to the user. The rest of
      # the pipeline runs in #resume_after_confirmation once they've
      # confirmed which matches to keep.
      match_ingredients_and_pause(scraped_data)
    rescue => e
      Rails.logger.error "=== IMPORT ERROR ==="
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.join("\n")

      @job.update!(
        status: :failed,
        error_message: e.message,
        current_step: "Error: #{e.message}"
      )
      raise
    end
  end

  def perform_from_file(file_data, content_type)
    begin
      # Step 1: Extract recipe from file via Claude
      @job.update_progress(:fetching_html) # reuse status — "Fetching file"
      sleep 0.3

      # Build a temporary file-like object from the raw bytes
      file_io = StringIO.new(file_data)
      file_io.define_singleton_method(:content_type) { content_type }
      file_io.define_singleton_method(:rewind) { seek(0) }

      scraped_data = RecipeFileExtractor.new(file_io).extract

      Rails.logger.info "=== FILE EXTRACTED DATA ==="
      Rails.logger.info "Title: #{scraped_data[:title]}"
      Rails.logger.info "Servings: #{scraped_data[:servings]}"
      Rails.logger.info "Ingredients (#{scraped_data[:ingredients]&.length || 0})"
      Rails.logger.info "Steps (#{scraped_data[:steps]&.length || 0})"

      @job.update!(scraped_data: scraped_data)

      # Steps 2–5 are identical to the URL import flow
      @job.update_progress(:parsing_recipe)
      sleep 0.3
      validate_scraped_data(scraped_data)

      match_ingredients_and_pause(scraped_data)
    rescue => e
      Rails.logger.error "=== FILE IMPORT ERROR ==="
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.join("\n")

      @job.update!(
        status: :failed,
        error_message: e.message,
        current_step: "Error: #{e.message}"
      )
      raise
    end
  end

  # Picks the import back up once the user has confirmed their ingredient
  # matches. Everything needed is on the job already (scraped_data and the
  # confirmed matched_ingredients), so this works from a fresh request —
  # no re-fetch or re-upload.
  def resume_after_confirmation
    scraped_data    = @job.scraped_data.deep_symbolize_keys
    matched_results = self.class.deserialize_results(@job.matched_ingredients)

    # Step 4: Families for everything, nutrition estimates for the new ones.
    # Matching is settled by now — the user decided — so nothing here
    # re-points an ingredient at a different match.
    @job.update_progress(:resolving_with_ai, 0, matched_results.length)
    classify_and_estimate_nutrition(matched_results)

    # Step 5: Create recipe in database
    @job.update_progress(:creating_recipe)
    sleep 0.3
    recipe = create_recipe(scraped_data, matched_results)

    @job.update!(
      status: :completed,
      recipe_id: recipe.id,
      progress: 100,
      current_step: 'Import completed!'
    )

    recipe
  rescue => e
    Rails.logger.error "=== IMPORT RESUME ERROR ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")

    @job.update!(
      status: :failed,
      error_message: e.message,
      current_step: "Error: #{e.message}"
    )
    raise
  end

  # The match rows are persisted across the confirmation pause, so they have
  # to survive a JSON round trip. Ingredients are stored by id and re-looked
  # up rather than serialized whole.
  def self.deserialize_results(raw)
    rows = Array(raw).select { |row| row.is_a?(Hash) }
    by_id = Ingredient.where(id: rows.filter_map { |row| row['match_id'] }).index_by(&:id)

    rows.map do |row|
      {
        parsed:     (row['parsed'] || {}).symbolize_keys,
        match:      by_id[row['match_id']],
        confidence: row['confidence'] || 0.0,
        method:     row['method'],
        confirmed:  row['confirmed'],
        family:     row['family'],
        nutrition:  row['nutrition']
      }
    end
  end

  private

  # Steps 3a/3b: fuzzy match, then let the AI take a pass at whatever came
  # back weak — so the confirmation screen shows our best proposal rather
  # than one the AI would have quietly overruled afterwards.
  def match_ingredients_and_pause(scraped_data)
    @job.update_progress(:matching_ingredients, 0, scraped_data[:ingredients].length)
    matched_results = match_ingredients(scraped_data[:ingredients])
    resolve_matches_with_ai(matched_results)

    @job.update!(
      matched_ingredients: serialize_results(matched_results),
      status:              :awaiting_confirmation,
      progress:            scraped_data[:ingredients].length,
      current_step:        'Confirm ingredient matches'
    )

    matched_results
  end

  def serialize_results(results)
    results.map do |result|
      {
        'parsed'     => result[:parsed].stringify_keys,
        'match_id'   => result[:match]&.id,
        'match_name' => result[:match]&.ingredient,
        'confidence' => result[:confidence],
        'method'     => result[:method],
        'confirmed'  => result[:confirmed],
        'family'     => result[:family],
        'nutrition'  => result[:nutrition]
      }
    end
  end

  def validate_scraped_data(data)
    errors = []
    errors << "No title found" if data[:title].blank?
    errors << "No ingredients found (#{data[:ingredients]&.length || 0} ingredients)" if data[:ingredients].blank? || data[:ingredients].empty?
    errors << "No steps found (#{data[:steps]&.length || 0} steps)" if data[:steps].blank? || data[:steps].empty?

    if errors.any?
      raise errors.join(". ")
    end
  end

  def match_ingredients(ingredient_strings)
    parser = IngredientParser.new
    matcher = IngredientMatcher.new

    ingredient_strings.map.with_index do |ing_str, index|
      parsed = parser.parse(ing_str)
      match_result = matcher.find_or_suggest(parsed)

      @job.update!(progress: index + 1)

      {
        parsed: parsed,
        match: match_result[:match],
        confidence: match_result[:confidence],
        method: match_result[:method],
        family: nil,
        nutrition: nil
      }
    end
  end

  # Gives the AI a shot at the ingredients fuzzy matching couldn't place, so
  # the user confirms the strongest proposal we can make. Runs before the
  # confirmation gate — afterwards the user's decisions are final.
  def resolve_matches_with_ai(matched_results)
    ai = OllamaAssistant.new(model: 'llama2')
    matcher = IngredientMatcher.new

    # Handle unmatched ingredients (low confidence)
    unmatched = matched_results.select { |r| r[:confidence] < 0.7 }
    if unmatched.any?
      Rails.logger.info "=== Resolving #{unmatched.length} unmatched ingredients with AI ==="

      # Give the AI a relevant shortlist per ingredient (via the same
      # fuzzy/Levenshtein ranking IngredientMatcher already uses) instead of
      # one arbitrary sample shared across all of them.
      unmatched_with_candidates = unmatched.map do |r|
        {
          ingredient: r[:parsed],
          candidates: matcher.candidates_for(r[:parsed][:search_name], limit: 10)
        }
      end

      ai_resolutions = ai.resolve_ingredients(unmatched_with_candidates)

      candidates_by_original = unmatched_with_candidates.each_with_object({}) do |entry, memo|
        memo[entry[:ingredient][:original]] = entry[:candidates]
      end

      # Update matched_results with AI suggestions
      ai_resolutions.each do |resolution|
        result = unmatched.find { |r| r[:parsed][:original] == resolution['original'] }
        next unless result

        if resolution['action'] == 'match' && resolution['match_name']
          allowed_candidates = candidates_by_original[resolution['original']] || []

          if allowed_candidates.any? { |candidate| candidate.casecmp?(resolution['match_name']) }
            ingredient = Ingredient.find_by('LOWER(ingredient) = ?', resolution['match_name'].downcase)
            if ingredient
              result[:match] = ingredient
              result[:confidence] = 0.75
              result[:method] = 'ai_match'
            end
          else
            Rails.logger.warn "AI suggested match_name #{resolution['match_name'].inspect} for #{resolution['original'].inspect} that wasn't in its candidate list — ignoring"
          end
        end

        # Use AI's family suggestion if available
        result[:family] = resolution['family'] if resolution['family']
      end
    end
  end

  # Post-confirmation work: every ingredient needs a family, and the ones the
  # user left unconfirmed are about to be created, so they need nutrition too.
  def classify_and_estimate_nutrition(matched_results)
    ai = OllamaAssistant.new(model: 'llama2')

    # Get all ingredients that need families (both matched and unmatched)
    all_ingredients = matched_results.map { |r| r[:parsed] }

    # Classify families for ALL ingredients
    Rails.logger.info "=== Classifying families for #{all_ingredients.length} ingredients ==="
    family_classifications = ai.classify_ingredient_families(all_ingredients)

    # Apply family classifications — without clobbering a family the AI
    # resolution step already picked during matching.
    matched_results.each do |result|
      next if result[:family].present?

      classification = family_classifications.find { |c| c['name'] == result[:parsed][:name] }
      if classification
        result[:family] = classification['family']
      else
        # Use programmatic fallback if AI didn't classify
        result[:family] = ai.send(:guess_family_programmatically, result[:parsed][:name])
      end
      Rails.logger.info "Ingredient: #{result[:parsed][:name]} -> Family: #{result[:family]}, Match: #{result[:match]&.ingredient || 'NEW'}"
    end

    # Estimate nutrition facts for NEW ingredients only (ones without a match)
    new_ingredients = matched_results.select { |r| r[:match].nil? }
    Rails.logger.info "=== Found #{new_ingredients.length} NEW ingredients that need nutrition facts ==="

    if new_ingredients.any?
      new_ingredients.each { |r| Rails.logger.info "  - #{r[:parsed][:name]} (family: #{r[:family]})" }

      ingredients_for_nutrition = new_ingredients.map do |r|
        { name: r[:parsed][:name], family: r[:family] }
      end

      nutrition_estimates = ai.estimate_nutrition_facts(ingredients_for_nutrition)
      Rails.logger.info "Got #{nutrition_estimates.length} nutrition estimates back from AI"

      # Apply nutrition estimates
      new_ingredients.each do |result|
        # Match by comparing the parsed name with nutrition estimate name
        ingredient_name = result[:parsed][:name]
        nutrition = nutrition_estimates.find { |n| n.is_a?(Hash) && n['name'] == ingredient_name }

        if nutrition
          Rails.logger.info "Applied nutrition for #{ingredient_name}: #{nutrition.inspect}"
          result[:nutrition] = nutrition
        else
          Rails.logger.warn "No nutrition estimate found for #{ingredient_name}"
          # If no match found, use fallback
          result[:nutrition] = ai.send(:fallback_nutrition_estimate, ingredient_name, result[:family])
        end
      end
    else
      Rails.logger.info "No new ingredients need nutrition facts"
    end
  end

  def create_recipe(scraped_data, matched_results)
    ActiveRecord::Base.transaction do
      # Create recipe
      recipe = Recipe.create!(
        title: scraped_data[:title],
        description: scraped_data[:description],
        servings: scraped_data[:servings] || 4,
        user: @job.user,
        visibility: 'public'   # imported recipes are always public
      )

      # Create recipe ingredients
      matched_results.each do |result|
        # Use existing ingredient OR create new one with nutrition
        ingredient = result[:match] || create_ingredient_with_nutrition(
          result[:parsed],
          result[:family],
          result[:nutrition]
        )

        RecipeIngredient.create!(
          recipe: recipe,
          ingredient: ingredient,
          quantity: result[:parsed][:quantity],
          unit: result[:parsed][:unit]
        )
      end

      # Create steps
      scraped_data[:steps].each_with_index do |step_text, index|
        recipe.steps.create!(
          position: index + 1,
          content: step_text
        )
      end

      recipe
    end
  end

  def create_ingredient_with_nutrition(parsed, family, nutrition)
    ingredient = Ingredient.create!(
      ingredient: parsed[:name],
      family: family || 'produce',
      unit_price: nutrition&.dig(:unit_price),
      unit_servings: nutrition&.dig(:unit_servings),
      created_by: @job.user
    )

    if nutrition && nutrition.is_a?(Hash)
      ingredient.create_nutrition_fact!(
        serving_size: nutrition[:serving_size],   # Changed to symbol
        serving_unit: nutrition[:serving_unit],   # Changed to symbol
        calories: nutrition[:calories],           # Changed to symbol
        protein: nutrition[:protein],             # Changed to symbol
        total_fat: nutrition[:total_fat],         # Changed to symbol
        total_carb: nutrition[:total_carb]        # Changed to symbol
      )
    end

    ingredient
  end
end