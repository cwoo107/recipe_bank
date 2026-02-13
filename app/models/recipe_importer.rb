# app/services/recipe_importer.rb
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

      # Step 3: Match ingredients
      @job.update_progress(:matching_ingredients, 0, scraped_data[:ingredients].length)
      matched_results = match_ingredients(scraped_data[:ingredients])
      @job.update!(matched_ingredients: matched_results)

      # Step 4: Resolve with AI (for matching AND family classification)
      @job.update_progress(:resolving_with_ai, 0, matched_results.length)
      classify_and_resolve_ingredients(matched_results)

      # Step 5: Create recipe in database
      @job.update_progress(:creating_recipe)
      sleep 0.5
      recipe = create_recipe(scraped_data, matched_results)

      # Done!
      @job.update!(
        status: :completed,
        recipe_id: recipe.id,
        progress: 100,
        current_step: 'Import completed!'
      )

      recipe
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

  private

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

  def classify_and_resolve_ingredients(matched_results)
    ai = OllamaAssistant.new(model: 'llama2')

    # Get all ingredients that need families (both matched and unmatched)
    all_ingredients = matched_results.map { |r| r[:parsed] }

    # Classify families for ALL ingredients
    Rails.logger.info "=== Classifying families for #{all_ingredients.length} ingredients ==="
    family_classifications = ai.classify_ingredient_families(all_ingredients)

    # Apply family classifications
    matched_results.each do |result|
      classification = family_classifications.find { |c| c['name'] == result[:parsed][:name] }
      if classification
        result[:family] = classification['family']
      else
        # Use programmatic fallback if AI didn't classify
        result[:family] = ai.send(:guess_family_programmatically, result[:parsed][:name])
      end
      Rails.logger.info "Ingredient: #{result[:parsed][:name]} -> Family: #{result[:family]}, Match: #{result[:match]&.ingredient || 'NEW'}"
    end

    # Handle unmatched ingredients (low confidence)
    unmatched = matched_results.select { |r| r[:confidence] < 0.7 }
    if unmatched.any?
      Rails.logger.info "=== Resolving #{unmatched.length} unmatched ingredients with AI ==="
      unmatched_parsed = unmatched.map { |r| r[:parsed] }
      existing_sample = Ingredient.limit(50).pluck(:ingredient)

      ai_resolutions = ai.resolve_ingredients(unmatched_parsed, existing_sample)

      # Update matched_results with AI suggestions
      ai_resolutions.each do |resolution|
        result = unmatched.find { |r| r[:parsed][:original] == resolution['original'] }
        next unless result

        if resolution['action'] == 'match' && resolution['match_name']
          ingredient = Ingredient.find_by('LOWER(ingredient) = ?', resolution['match_name'].downcase)
          if ingredient
            result[:match] = ingredient
            result[:confidence] = 0.75
            result[:method] = 'ai_match'
          end
        end

        # Use AI's family suggestion if available
        result[:family] = resolution['family'] if resolution['family']
      end
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
        servings: scraped_data[:servings] || 4
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
      unit_price: nutrition&.dig(:unit_price),      # Changed to symbol
      unit_servings: nutrition&.dig(:unit_servings) # Changed to symbol
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