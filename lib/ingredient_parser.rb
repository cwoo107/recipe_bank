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
    fl\ oz stick sticks box boxes jar jars envelope envelopes
    sprig sprigs head heads stalk stalks
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

  # Connector words that introduce an additional quantity+unit clause, e.g.
  # "1 tablespoon plus 1 teaspoon kosher salt, divided"
  QUANTITY_CONNECTORS = %w[plus and]

  LEADING_QUANTITY_REGEX = /^\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?(?:\s+\d+\/\d+)?/

  def parse(ingredient_string)
    original = ingredient_string.strip
    text = normalize_fractions(original)

    # Pre-process: strip parenthetical quantity annotations that appear before
    # the actual ingredient name. Recipes often format ingredients as:
    #   "(4 cups) all purpose flour"     <- leading qty annotation
    #   "1 (15-oz) can black beans"      <- inline size annotation
    # Both patterns must be removed before quantity/unit extraction.
    text = strip_parenthetical_annotations(text)

    quantity = extract_quantity(text)
    unit     = extract_unit(text)
    name     = extract_name(text, quantity, unit)

    {
      original: original,
      quantity: quantity,
      unit: unit,
      name: name,
      search_name: self.class.normalize_for_search(name)
    }
  end

  # Canonical normalization used both when parsing fresh ingredient text and
  # when comparing it against ingredient names already stored in the
  # database (see IngredientMatcher). Keeping this in one place means both
  # sides of a match always agree on what "the same ingredient" looks like,
  # instead of drifting apart the way two separately-maintained descriptor
  # lists would.
  def self.normalize_for_search(str)
    return '' unless str

    text = str.to_s.downcase
    DESCRIPTORS.each do |descriptor|
      text = text.gsub(/\b#{Regexp.escape(descriptor)}\b/, '')
    end
    text.gsub(/[^a-z\s]/, '').gsub(/\s+/, ' ').strip
  end

  private

  # Remove parenthetical annotations that carry quantity/size info rather than
  # ingredient detail. We strip:
  #   1. A leading "(qty unit)" block: "(4 cups) flour" -> "4 cups flour"
  #      so the normal qty/unit extraction can handle it.
  #   2. Inline size qualifiers after a digit: "1 (15-oz) can" -> "1 can"
  #      These are redundant — the outer quantity already captures the amount.
  #
  # We deliberately keep parentheticals that describe ingredient state/variety
  # (e.g., "tomatoes (crushed)") — those are stripped later in extract_name.
  def strip_parenthetical_annotations(text)
    # Pattern 1: leading "(number unit)" — move the number+unit out of parens
    # "(4 cups) all purpose flour" -> "4 cups all purpose flour"
    text = text.sub(/^\((\d[^)]*)\)\s*/, '\1 ')

    # Pattern 2: inline "(size-unit)" after an outer quantity
    # "1 (15-oz) can" -> "1 can"
    # "2 (14.5-ounce) cans" -> "2 cans"
    unit_pattern = UNITS.map { |u| Regexp.escape(u) }.join('|')
    text = text.gsub(/\(\d[\d\s\/\-\.]*(?:#{unit_pattern})\)/i, '').gsub(/\s+/, ' ').strip

    text
  end

  def normalize_fractions(text)
    # Mixed numbers ("1 1/2", "2 ¾") must be collapsed to a single decimal
    # *before* the standalone-fraction pass below. Otherwise replacing just
    # the fractional part turns "1 1/2 cups" into "1 0.5 cups" — the whole
    # number and fraction never recombine, "1" gets extracted as the
    # quantity, and "0.5 cups" leaks straight into the ingredient name.
    FRACTIONS.each do |fraction, decimal|
      text = text.gsub(/(\d+)\s+#{Regexp.escape(fraction)}/) { ($1.to_f + decimal).to_s }
    end

    # Any remaining standalone fraction (not part of a mixed number)
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
      whole    = parts[0].to_f
      fraction = parts[1] ? parse_fraction(parts[1]) : 0
      return whole + fraction
    end

    qty_text.to_f
  end

  def parse_fraction(fraction_text)
    numerator, denominator = fraction_text.split('/')
    numerator.to_f / denominator.to_f
  end

  def extract_unit(text)
    text_without_qty = text.sub(LEADING_QUANTITY_REGEX, '').strip
    match_leading_unit(text_without_qty)&.dig(:unit)
  end

  def extract_name(text, quantity, unit)
    # Remove quantity
    name = text.sub(LEADING_QUANTITY_REGEX, '').strip

    # Remove unit — reuses the exact same match that extract_unit found, so
    # detection and removal can never disagree with each other.
    if unit
      match = match_leading_unit(name)
      name = name.sub(match[:pattern], '').strip if match
    end

    # Handle compound quantities like "plus 1 teaspoon kosher salt, divided"
    name = strip_connector_quantity_clauses(name)

    # Remove common prefixes like "of"
    name = name.sub(/^of\s+/i, '').strip

    # Remove ALL parentheticals — both inline annotations that survived
    # strip_parenthetical_annotations and trailing prep notes like "(crushed)"
    name = strip_parentheticals(name)

    # Remove descriptors
    DESCRIPTORS.each do |descriptor|
      name = name.gsub(/\b#{Regexp.escape(descriptor)}\b/i, '').strip
    end

    # Remove trailing preparation notes after comma
    name = name.sub(/,.*$/, '').strip

    # Clean up multiple spaces
    name.gsub(/\s+/, ' ').strip
  end

  # Handles ingredient strings with more than one quantity clause, e.g.
  # "1 tablespoon plus 1 teaspoon kosher salt, divided". The initial
  # "1 tablespoon" is already stripped by the time this runs; this strips any
  # further "<connector> <qty> <unit>" clauses so only the ingredient name
  # remains. Only fires when a recognized unit follows the number, so plain
  # language like "black and white sesame seeds" is left untouched.
  def strip_connector_quantity_clauses(name)
    connector_pattern = QUANTITY_CONNECTORS.join('|')

    loop do
      match = name.match(/^(?:#{connector_pattern})\s+(\d+(?:\.\d+)?(?:\s+\d+\/\d+)?)\s+(.*)$/i)
      break unless match

      remainder = match[2]
      unit_match = match_leading_unit(remainder)
      break unless unit_match

      name = remainder.sub(unit_match[:pattern], '').strip
    end

    name
  end

  # Removes parenthetical asides, including nested ones, e.g.
  # "cheese (cheddar or Monterey Jack (or a blend))" -> "cheese". A single
  # gsub can't handle nesting since `[^)]*` stops at the first `)` it finds,
  # leaving the outer `)` stranded — so we strip innermost pairs repeatedly
  # until none remain.
  def strip_parentheticals(name)
    loop do
      stripped = name.gsub(/\([^()]*\)/, '')
      break if stripped == name

      name = stripped
    end
    name.strip
  end

  # Finds the unit at the very start of `text`, if any. Returns the pattern
  # that matched (so callers can strip that exact text) and the standardized
  # unit name. Bare "T"/"t" are checked case-sensitively ahead of the
  # generic case-insensitive unit list, since they mean different things
  # (tablespoon vs. teaspoon) and would otherwise collide under /i.
  def match_leading_unit(text)
    return { pattern: /^T\b/, unit: 'tablespoon' } if text.match?(/^T\b/)
    return { pattern: /^t\b/, unit: 'teaspoon' } if text.match?(/^t\b/)

    UNITS.each do |unit|
      pattern = /^\b#{Regexp.escape(unit)}\b/i
      return { pattern: pattern, unit: standardize_unit(unit) } if text.match?(pattern)
    end

    nil
  end

  def standardize_unit(unit)
    unit = unit.downcase

    case unit
    when 'cups', 'c'                  then 'cup'
    when 'tablespoons', 'tbsp', 'tbs' then 'tablespoon'
    when 'teaspoons', 'tsp'           then 'teaspoon'
    when 'ounces', 'oz'                then 'ounce'
    when 'pounds', 'lbs', 'lb'         then 'pound'
    when 'grams', 'g'                  then 'gram'
    when 'kilograms', 'kg'             then 'kilogram'
    when 'milliliters', 'ml'           then 'milliliter'
    when 'liters', 'l'                 then 'liter'
    when 'fl oz'                       then 'fluid ounce'
    when 'sticks'                      then 'stick'
    when 'boxes'                       then 'box'
    when 'jars'                        then 'jar'
    when 'envelopes'                   then 'envelope'
    when 'sprigs'                      then 'sprig'
    when 'heads'                       then 'head'
    when 'stalks'                      then 'stalk'
    else unit
    end
  end
end
