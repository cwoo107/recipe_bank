# lib/tasks/import_products.rake
namespace :products do
  desc "Import a single product from Trader Joe's URL"
  task :import, [:url] => :environment do |t, args|
    unless args[:url]
      puts "Usage: rake products:import[https://www.traderjoes.com/home/products/pdp/...]"
      exit
    end

    puts "Fetching product from #{args[:url]}..."

    begin
      scraper = TraderjoesScraper.new(args[:url])
      product_data = scraper.scrape

      puts "\nProduct Found:"
      puts "  Name: #{product_data[:name]}"
      puts "  Price: $#{product_data[:price]}"
      puts "  Category: #{product_data[:category]}"

      # Determine family
      ai = OllamaAssistant.new(model: 'llama2')
      family = determine_family(product_data[:name], product_data[:category], ai)

      # Check if exists
      existing = Ingredient.find_by('LOWER(ingredient) = ?', product_data[:name].downcase)

      if existing
        puts "\n⚠️  Ingredient already exists: #{product_data[:name]}"
        exit
      end

      # Estimate servings
      servings = estimate_servings(product_data[:price])

      # Create ingredient
      ingredient = Ingredient.create!(
        ingredient: product_data[:name],
        family: family,
        unit_price: product_data[:price],
        unit_servings: servings
      )

      puts "\n✅ Created ingredient ##{ingredient.id}"
      puts "   Family: #{family}"
      puts "   Unit Price: $#{ingredient.unit_price}"
      puts "   Unit Servings: #{ingredient.unit_servings}"

      # Create nutrition facts if available
      if product_data[:nutrition]
        create_nutrition_fact(ingredient, product_data[:nutrition])
        puts "   Nutrition facts: ✅"
      else
        puts "   Nutrition facts: ❌ (not found)"
      end

    rescue => e
      puts "\n❌ Error: #{e.message}"
      puts e.backtrace.first(3)
    end
  end

  desc "Import multiple products from a Trader Joe's category page"
  task :import_category, [:url, :limit] => :environment do |t, args|
    unless args[:url]
      puts "Usage: rake products:import_category[https://www.traderjoes.com/home/discover/...,10]"
      exit
    end

    limit = args[:limit]&.to_i || 10

    puts "Fetching products from category page..."

    begin
      product_urls = TraderjoesScraper.scrape_category(args[:url])

      puts "Found #{product_urls.length} products"
      puts "Importing up to #{limit} products...\n"

      ai = OllamaAssistant.new(model: 'llama2')
      imported = 0
      skipped = 0
      failed = 0

      product_urls.first(limit).each_with_index do |product_url, index|
        print "\n[#{index + 1}/#{[limit, product_urls.length].min}] "

        begin
          scraper = TraderjoesScraper.new(product_url)
          product_data = scraper.scrape

          print "#{product_data[:name]}... "

          # Check if exists
          existing = Ingredient.find_by('LOWER(ingredient) = ?', product_data[:name].downcase)

          if existing
            print "skipped (exists)\n"
            skipped += 1
            next
          end

          # Determine family
          family = determine_family(product_data[:name], product_data[:category], ai)
          servings = estimate_servings(product_data[:price])

          # Create ingredient
          ingredient = Ingredient.create!(
            ingredient: product_data[:name],
            family: family,
            unit_price: product_data[:price],
            unit_servings: servings
          )

          # Create nutrition facts if available
          if product_data[:nutrition]
            create_nutrition_fact(ingredient, product_data[:nutrition])
          end

          print "✅ imported (#{family})\n"
          imported += 1

          sleep 0.5 # Be nice to their servers

        rescue => e
          print "❌ failed (#{e.message})\n"
          failed += 1
        end
      end

      puts "\n" + "="*50
      puts "Summary:"
      puts "  Imported: #{imported}"
      puts "  Skipped:  #{skipped}"
      puts "  Failed:   #{failed}"
      puts "="*50

    rescue => e
      puts "\n❌ Error: #{e.message}"
    end
  end

  desc "List available Trader Joe's categories"
  task :list_categories => :environment do
    puts "Common Trader Joe's category URLs:"
    puts "  Dairy: https://www.traderjoes.com/home/discover/products/dairy"
    puts "  Meat & Seafood: https://www.traderjoes.com/home/discover/products/meat-seafood"
    puts "  Produce: https://www.traderjoes.com/home/discover/products/produce"
    puts "  Frozen: https://www.traderjoes.com/home/discover/products/frozen"
    puts "  Pantry: https://www.traderjoes.com/home/discover/products/pantry"
    puts ""
    puts "Usage:"
    puts "  rake products:import_category['URL',LIMIT]"
  end

  # Helper methods
  def determine_family(name, category, ai)
    family = ai.send(:guess_family_programmatically, name)

    if category
      category_lower = category.downcase

      return 'protein' if category_lower.match?(/meat|seafood|protein/)
      return 'produce' if category_lower.match?(/produce|fruit|vegetable/)
      return 'dairy' if category_lower.match?(/dairy|cheese|milk/)
      return 'grain' if category_lower.match?(/bread|bakery|grain/)
      return 'spices' if category_lower.match?(/spice|seasoning/)
    end

    family
  end

  def estimate_servings(price)
    return 4 unless price

    case price
    when 0..3 then 2
    when 3..6 then 4
    when 6..10 then 8
    else 10
    end
  end

  def create_nutrition_fact(ingredient, nutrition_data)
    return unless nutrition_data[:calories] || nutrition_data[:protein]

    ingredient.create_nutrition_fact!(
      serving_size: nutrition_data[:serving_size] || 1,
      serving_unit: nutrition_data[:serving_unit] || 'serving',
      calories: nutrition_data[:calories],
      protein: nutrition_data[:protein],
      total_fat: nutrition_data[:total_fat],
      total_carb: nutrition_data[:total_carb]
    )
  rescue => e
    # Silently fail nutrition fact creation
  end
end