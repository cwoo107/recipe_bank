# lib/recipe_scraper.rb
require 'nokogiri'
require 'open-uri'
require 'json'

class RecipeScraper
  attr_reader :url, :doc

  def initialize(url)
    @url = url
  end

  def scrape
    @doc = fetch_html

    # Try schema.org first (most reliable)
    schema_data = extract_schema_recipe
    return schema_data if schema_data

    # Fallback to HTML parsing
    extract_from_html
  end

  private

  def fetch_html
    html = URI.open(url, 'User-Agent' => 'Mozilla/5.0').read
    Nokogiri::HTML(html)
  rescue => e
    raise "Failed to fetch URL: #{e.message}"
  end

  def extract_schema_recipe
    script_tags = doc.css('script[type="application/ld+json"]')

    script_tags.each do |script|
      begin
        data = JSON.parse(script.content)

        # Skip if data is not a hash or array
        next unless data.is_a?(Hash) || data.is_a?(Array)

        recipes = data.is_a?(Array) ? data : [data]

        # Handle nested @graph structures
        if data.is_a?(Hash) && data['@graph']
          recipes = data['@graph']
        end

        recipe = recipes.find { |r| r.is_a?(Hash) && r['@type'] == 'Recipe' }

        if recipe
          return {
            title: recipe['name'],
            description: clean_text(recipe['description']),
            servings: extract_servings(recipe['recipeYield']),
            ingredients: extract_schema_ingredients(recipe['recipeIngredient'] || []),
            steps: extract_schema_instructions(recipe['recipeInstructions'] || []),
            image_url: extract_image(recipe['image'])
          }
        end
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse JSON-LD: #{e.message}"
        next
      rescue => e
        Rails.logger.warn "Error processing schema: #{e.message}"
        next
      end
    end

    nil
  end

  def extract_schema_ingredients(ingredients)
    case ingredients
    when Array
      ingredients.map { |ing| clean_text(ing) }
    when String
      [clean_text(ingredients)]
    else
      []
    end
  end

  def extract_schema_instructions(instructions)
    case instructions
    when Array
      instructions.map do |step|
        if step.is_a?(Hash)
          clean_text(step['text'] || step['name'] || '')
        else
          clean_text(step)
        end
      end.reject(&:empty?)
    when String
      [clean_text(instructions)]
    when Hash
      [clean_text(instructions['text'] || '')]
    else
      []
    end
  end

  def extract_from_html
    {
      title: extract_title,
      description: extract_description,
      servings: extract_servings_from_html,
      ingredients: extract_ingredients_from_html,
      steps: extract_steps_from_html,
      image_url: extract_image_from_html
    }
  end

  def extract_title
    candidates = [
      doc.at_css('h1.recipe-title'),
      doc.at_css('.recipe-header h1'),
      doc.at_css('h1[itemprop="name"]'),
      doc.at_css('h1')
    ]

    candidates.compact.first&.text&.strip || 'Untitled Recipe'
  end

  def extract_description
    candidates = [
      doc.at_css('[itemprop="description"]'),
      doc.at_css('.recipe-description'),
      doc.at_css('meta[name="description"]')&.[]('content')
    ]

    clean_text(candidates.compact.first&.text)
  end

  def extract_servings_from_html
    text = doc.at_css('[itemprop="recipeYield"]')&.text ||
      doc.at_css('.recipe-yield')&.text ||
      doc.at_css('.servings')&.text

    extract_servings(text)
  end

  def extract_ingredients_from_html
    selectors = [
      '.wprm-recipe-ingredient',
      '.recipe-ingredients li',
      '.ingredient-list li',
      '[itemprop="recipeIngredient"]',
      '.tasty-recipes-ingredients li',
      '.mv-create-ingredients li'
    ]

    selectors.each do |selector|
      items = doc.css(selector)
      if items.any?
        return items.map { |i| clean_text(i.text) }.reject(&:empty?)
      end
    end

    []
  end

  def extract_steps_from_html
    selectors = [
      '.wprm-recipe-instruction-text',
      '.recipe-instructions li',
      '.instructions li',
      '[itemprop="recipeInstructions"] li',
      '.tasty-recipes-instructions li',
      '.mv-create-instructions li'
    ]

    selectors.each do |selector|
      items = doc.css(selector)
      if items.any?
        return items.map { |i| clean_text(i.text) }.reject(&:empty?)
      end
    end

    # Fallback: try to get instruction text as paragraphs
    instruction_section = doc.at_css('[itemprop="recipeInstructions"]')
    if instruction_section
      return instruction_section.css('p').map { |p| clean_text(p.text) }.reject(&:empty?)
    end

    []
  end

  def extract_image(image_data)
    case image_data
    when Array
      image_data.first
    when Hash
      image_data['url']
    when String
      image_data
    else
      nil
    end
  end

  def extract_image_from_html
    candidates = [
      doc.at_css('[itemprop="image"]')&.[]('src'),
      doc.at_css('.recipe-image img')&.[]('src'),
      doc.at_css('meta[property="og:image"]')&.[]('content')
    ]

    candidates.compact.first
  end

  def extract_servings(yield_text)
    return nil unless yield_text

    # Extract first number from text like "Serves 4" or "4 servings"
    text = yield_text.to_s
    match = text.match(/(\d+)/)
    match ? match[1].to_i : nil
  end

  def clean_text(text)
    return '' unless text
    text.to_s.gsub(/\s+/, ' ').strip
  end
end