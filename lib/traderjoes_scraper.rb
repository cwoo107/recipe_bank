# lib/traderjoes_scraper.rb
require 'selenium-webdriver'
require 'nokogiri'

class TraderjoesScraper
  attr_reader :url

  def initialize(url, debug: false)
    @url = url
    @debug = debug
  end

  def scrape
    driver = setup_driver

    begin
      puts "Loading page..."
      driver.get(url)

      # Wait for page to load
      wait = Selenium::WebDriver::Wait.new(timeout: 10)
      wait.until { driver.find_element(css: 'body') }

      # Additional wait for dynamic content
      sleep 3

      html = driver.page_source

      # Save HTML for debugging
      if @debug
        File.write('debug_traderjoes.html', html)
        puts "Saved HTML to debug_traderjoes.html"
      end

      doc = Nokogiri::HTML(html)

      extract_product_data(doc)
    ensure
      driver.quit
    end
  end

  def self.scrape_category(category_url)
    driver = setup_driver

    begin
      puts "Loading category page..."
      driver.get(category_url)

      # Wait for products to load
      wait = Selenium::WebDriver::Wait.new(timeout: 10)
      wait.until { driver.find_elements(css: 'a').any? }

      sleep 3

      # Scroll to load more products
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
      sleep 2

      html = driver.page_source
      doc = Nokogiri::HTML(html)

      # Find all product links
      product_links = doc.css('a[href*="/products/pdp/"]').map do |link|
        href = link['href']
        href.start_with?('http') ? href : "https://www.traderjoes.com#{href}"
      end.uniq

      product_links
    ensure
      driver.quit
    end
  rescue => e
    puts "Failed to scrape category: #{e.message}"
    []
  end

  private

  def setup_driver
    self.class.setup_driver
  end

  def self.setup_driver
    options = Selenium::WebDriver::Chrome::Options.new

    # Run headless
    options.add_argument('--headless=new')

    # Anti-detection measures
    options.add_argument('--disable-blink-features=AutomationControlled')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-software-rasterizer')

    # Realistic user agent
    options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    # Window size
    options.add_argument('--window-size=1920,1080')

    # Additional options
    options.add_preference(:excludeSwitches, ['enable-automation'])
    options.add_preference(:useAutomationExtension, false)

    # Let Selenium Manager handle the driver
    service = Selenium::WebDriver::Service.chrome

    Selenium::WebDriver.for :chrome, service: service, options: options
  rescue Selenium::WebDriver::Error::WebDriverError => e
    puts "\nError setting up Chrome driver: #{e.message}"
    puts "\nTrying with system Chrome..."

    chrome_paths = [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/usr/bin/google-chrome',
      '/usr/bin/chromium-browser'
    ]

    chrome_path = chrome_paths.find { |path| File.exist?(path) }

    if chrome_path
      options.binary = chrome_path
      Selenium::WebDriver.for :chrome, options: options
    else
      raise "Chrome not found. Please install Google Chrome or Chromium."
    end
  end

  def extract_product_data(doc)
    name = extract_name(doc)
    price = extract_price(doc)
    category = extract_category(doc)
    nutrition = extract_nutrition_facts(doc)

    {
      name: name,
      price: price,
      category: category,
      nutrition: nutrition,
      url: url
    }
  end

  def extract_name(doc)
    selectors = [
      'h1',
      '[class*="productTitle"]',
      '[class*="ProductTitle"]'
    ]

    selectors.each do |selector|
      elements = doc.css(selector)
      elements.each do |element|
        text = clean_text(element.text)
        return text if text.present? && text.length > 3
      end
    end

    ''
  end

  def extract_price(doc)
    selectors = [
      '[class*="price"]',
      '[class*="Price"]'
    ]

    selectors.each do |selector|
      elements = doc.css(selector)
      elements.each do |element|
        price_text = element.text
        if match = price_text.match(/\$?([\d.]+)/)
          price = match[1].to_f
          return price if price > 0 && price < 1000
        end
      end
    end

    nil
  end

  def extract_category(doc)
    # Look for breadcrumbs
    breadcrumb = doc.at_css('.BreadcrumbList_list__2ApaY')
    if breadcrumb
      links = breadcrumb.css('a')
      # Get the last meaningful breadcrumb (skip Home)
      links.each do |link|
        text = clean_text(link.text)
        next if text.match?(/^(Home|Products)$/i)
        return text if text.present?
      end
    end

    nil
  end

  def extract_nutrition_facts(doc)
    nutrition = {}

    # Find the nutrition facts section
    nutrition_section = doc.at_css('.NutritionFacts_nutritionFacts__1Nvz0')

    return nil unless nutrition_section

    # Extract serving size
    serving_element = nutrition_section.at_css('.Item_characteristics__item__2TgL-:has(.Item_characteristics__title__7nfa8:contains("serving size")) .Item_characteristics__text__dcfEC')
    if serving_element
      serving_text = serving_element.text.strip
      # Parse "1 cup(240ml)"
      nutrition[:serving_size], nutrition[:serving_unit] = parse_serving_size(serving_text)
    end

    # Extract calories
    calories_element = nutrition_section.at_css('.Item_characteristics__item__2TgL-:has(.Item_characteristics__title__7nfa8:contains("calories")) .Item_characteristics__text__dcfEC')
    if calories_element
      nutrition[:calories] = calories_element.text.strip.to_i
    end

    # Extract from table
    table = nutrition_section.at_css('.Item_table__2PMbE')
    if table
      table.css('tbody tr').each do |row|
        label = row.at_css('th')&.text&.strip&.downcase
        value_cell = row.css('td')[0] # First td has the amount

        next unless label && value_cell

        value_text = value_cell['title'] || value_cell.text

        case label
        when 'total fat'
          if match = value_text.match(/([\d.]+)\s*g/)
            nutrition[:total_fat] = match[1].to_f
          end
        when 'protein'
          if match = value_text.match(/([\d.]+)\s*g/)
            nutrition[:protein] = match[1].to_f
          end
        when 'total carbohydrate'
          if match = value_text.match(/([\d.]+)\s*g/)
            nutrition[:total_carb] = match[1].to_f
          end
        end
      end
    end

    nutrition.any? ? nutrition : nil
  end

  def parse_serving_size(text)
    # Parse "1 cup(240ml)" or "2 tbsp(30g)"
    text = text.gsub(/[()]/,'')  # Remove parentheses

    if match = text.match(/(\d+(?:\.\d+)?)\s*([a-z]+)/i)
      amount = match[1].to_f
      unit = match[2].downcase

      # Standardize units
      unit = case unit
             when 'cups', 'c' then 'cup'
             when 'tablespoons', 'tbsp', 'tbs' then 'tbsp'
             when 'teaspoons', 'tsp' then 'tsp'
             when 'ounces', 'oz' then 'oz'
             else unit
             end

      [amount, unit]
    else
      [1.0, 'serving']
    end
  end

  def clean_text(text)
    return '' unless text
    text.to_s.gsub(/\s+/, ' ').strip
  end
end