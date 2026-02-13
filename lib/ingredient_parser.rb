# lib/ingredient_parser.rb
class IngredientParser
  FRACTIONS = {
    '½' => 0.5, '⅓' => 0.33, '⅔' => 0.67, '¼' => 0.25, '¾' => 0.75,
    '⅕' => 0.2, '⅖' => 0.4, '⅗' => 0.6, '⅘' => 0.8, '⅙' => 0.17,
    '⅚' => 0.83, '⅛' => 0.125, '⅜' => 0.375, '⅝' => 0.625, '⅞' => 0.875,
    '1/2' => 0.5, '1/3' => 0.33, '2/3' => 0.67, '1/4' => 0.25, '3/4' => 0.75
  }

  UNITS = %w[
    cup cups c tablespoon tablespoons tbsp tbs teaspoon teaspoons tsp
    ounce ounces oz pound pounds lb lbs gram grams g kilogram kilograms kg
    milliliter milliliters ml liter liters l pint pints pt quart quarts qt
    gallon gallons gal pinch dash clove cloves slice slices can cans
    package packages pkg bunch bunches
  ]

  # Descriptors to remove from ingredient names
  DESCRIPTORS = %w[
    large small medium extra jumbo baby mini
    fresh frozen dried canned
    organic free-range grass-fed wild-caught
    whole halved quartered sliced diced chopped minced
    shredded grated crushed ground
    boneless skinless seedless
    raw cooked uncooked
    ripe unripe
  ]

  def parse(ingredient_string)
    original = ingredient_string.strip
    text = normalize_fractions(original)

    quantity = extract_quantity(text)
    unit = extract_unit(text)
    name = extract_name(text, quantity, unit)

    {
      original: original,
      quantity: quantity,
      unit: unit,
      name: name,
      search_name: normalize_for_search(name)
    }
  end

  private

  def normalize_fractions(text)
    FRACTIONS.each do |fraction, decimal|
      text = text.gsub(fraction, decimal.to_s)
    end
    text
  end

  def extract_quantity(text)
    # Match patterns like: "2", "2.5", "1 1/2", "2-3"
    match = text.match(/^(\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?(?:\s+\d+\/\d+)?)/)
    return nil unless match

    qty_text = match[1]

    # Handle ranges (take average)
    if qty_text.include?('-')
      parts = qty_text.split('-').map(&:to_f)
      return (parts[0] + parts[1]) / 2.0
    end

    # Handle mixed numbers like "1 1/2"
    if qty_text.include?('/')
      parts = qty_text.split
      whole = parts[0].to_f
      fraction = parts[1] ? eval(parts[1]) : 0
      return whole + fraction
    end

    qty_text.to_f
  end

  def extract_unit(text)
    # Remove quantity first
    text_without_qty = text.sub(/^\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?(?:\s+\d+\/\d+)?/, '').strip

    # Look for unit at the beginning
    UNITS.each do |unit|
      if text_without_qty.match?(/^\b#{Regexp.escape(unit)}\b/i)
        return standardize_unit(unit)
      end
    end

    nil
  end

  def extract_name(text, quantity, unit)
    # Remove quantity
    name = text.sub(/^\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?(?:\s+\d+\/\d+)?/, '').strip

    # Remove unit
    if unit
      UNITS.each do |u|
        name = name.sub(/^\b#{Regexp.escape(u)}\b/i, '').strip
      end
    end

    # Remove common prefixes like "of"
    name = name.sub(/^of\s+/i, '').strip

    # Remove descriptors
    DESCRIPTORS.each do |descriptor|
      name = name.gsub(/\b#{Regexp.escape(descriptor)}\b/i, '').strip
    end

    # Remove trailing instructions in parentheses
    name = name.sub(/\([^)]+\)$/, '').strip

    # Remove trailing preparation notes after comma
    name = name.sub(/,.*$/, '').strip

    # Clean up multiple spaces
    name = name.gsub(/\s+/, ' ').strip

    name
  end

  def standardize_unit(unit)
    unit = unit.downcase

    case unit
    when 'cups', 'c' then 'cup'
    when 'tablespoons', 'tbsp', 'tbs' then 'tablespoon'
    when 'teaspoons', 'tsp' then 'teaspoon'
    when 'ounces', 'oz' then 'ounce'
    when 'pounds', 'lbs', 'lb' then 'pound'
    when 'grams', 'g' then 'gram'
    when 'kilograms', 'kg' then 'kilogram'
    when 'milliliters', 'ml' then 'milliliter'
    when 'liters', 'l' then 'liter'
    else unit
    end
  end

  def normalize_for_search(name)
    name.downcase
        .gsub(/[^a-z\s]/, '')
        .gsub(/\s+/, ' ')
        .strip
  end
end