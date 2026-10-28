# lib/recipe_scraper.rb
require 'nokogiri'
require 'json'

class RecipeScraper
  attr_reader :url, :doc

  def initialize(url)
    @url = url
  end

  def scrape
    @doc = fetch_html
    scrape_document
  end

  # Split from #scrape so tests can hand it a page without fetching one.
  def scrape_document
    # Try schema.org first (most reliable)
    schema_data = extract_schema_recipe
    return schema_data if schema_data

    # Fallback to HTML parsing
    extract_from_html
  end

  private

  # The URL is whatever the user typed, so it goes through SafeUrlFetcher —
  # its errors are already worded for the user.
  def fetch_html
    html, charset = SafeUrlFetcher.new(url).fetch
    Nokogiri::HTML(html, nil, charset)
  end

  def extract_schema_recipe
    script_tags = doc.css('script[type="application/ld+json"]')

    script_tags.each do |script|
      begin
        data = JSON.parse(script.content)

        recipe = find_schema_recipe(data)

        if recipe
          return {
            title: clean_text(recipe['name']).presence,
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

  # The Recipe node can be the top-level object, one of an array of them, or
  # inside an @graph — at any of those levels — and its @type can be a list
  # ("Recipe" alongside "NewsArticle", say).
  def find_schema_recipe(node, depth = 0)
    return nil if depth > 5

    case node
    when Array
      node.each do |item|
        found = find_schema_recipe(item, depth + 1)
        return found if found
      end
      nil
    when Hash
      return node if Array(node['@type']).include?('Recipe')
      find_schema_recipe(node['@graph'], depth + 1) if node['@graph']
    end
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
      instructions.flat_map { |step| extract_instruction_step(step) }.reject(&:empty?)
    when String
      [clean_text(instructions)]
    when Hash
      extract_instruction_step(instructions).reject(&:empty?)
    else
      []
    end
  end

  # Handle a single instruction node, which may be:
  #   HowToStep  — has 'text' (the actual instruction body)
  #   HowToSection — has 'name' (section header) and 'itemListElement' (nested steps)
  #
  # Many recipe sites wrap steps in sections like:
  #   { "@type": "HowToSection", "name": "Make the Dough",
  #     "itemListElement": [ { "@type": "HowToStep", "text": "..." }, ... ] }
  #
  # We flatten sections into a plain step list. The section name is prepended
  # as a context line only when it adds meaning (i.e. there are multiple sections),
  # which RecipeImporter handles naturally since steps are just an array of strings.
  def extract_instruction_step(step)
    return [clean_text(step)] unless step.is_a?(Hash)

    type = Array(step['@type']).map(&:to_s)

    if type.include?('HowToSection') || step.key?('itemListElement')
      # Flatten nested steps from this section
      nested = Array(step['itemListElement'])
      extracted = nested.flat_map { |s| extract_instruction_step(s) }.reject(&:empty?)

      # Prepend section name as a label if it exists and there are steps under it
      section_name = clean_text(step['name'].to_s)
      if section_name.present? && extracted.any?
        # Attach the section name to the first step so it reads naturally
        # e.g. "Make the Dough: Combine flour and salt in a large bowl."
        first = "#{section_name}: #{extracted.first}"
        [first] + extracted[1..]
      else
        extracted
      end
    else
      # HowToStep or plain hash — prefer 'text' (full instruction) over 'name' (short label)
      text = clean_text(step['text'].to_s)
      text = clean_text(step['name'].to_s) if text.empty?
      [text]
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

    # nil rather than a placeholder, so the importer's "No title found" check
    # can catch a page we couldn't read.
    candidates.compact.first&.text&.strip.presence
  end

  def extract_description
    candidates = [
      doc.at_css('[itemprop="description"]')&.text,
      doc.at_css('.recipe-description')&.text,
      doc.at_css('meta[name="description"]')&.[]('content')
    ]

    clean_text(candidates.compact.first)
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

  # JSON-LD text often arrives HTML-encoded ("Mom&#8217;s Pie") and sometimes
  # with tags in it; parsing it as a fragment decodes the one and drops the
  # other. Text read out of the page's HTML is already decoded and passes
  # through unchanged.
  def clean_text(text)
    return '' unless text
    text = text.to_s
    text = Nokogiri::HTML.fragment(text).text if text.match?(/[&<]/)
    text.gsub(/\s+/, ' ').strip
  end
end