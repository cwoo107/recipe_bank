module GroceryListsHelper
  FRACTIONS = { 0.25 => "¼", 1.0 / 3 => "⅓", 0.5 => "½", 2.0 / 3 => "⅔", 0.75 => "¾" }.freeze
  # Kitchen measures read best as fractions; metric ones as plain numbers.
  FRACTION_UNITS = %w[tsp tbsp cup pint quart fl\ oz oz lb].freeze
  # Units that take an "s" past one ("3 cups", but "3 tbsp", "300 g").
  PLURAL_UNITS = { "cup" => "cups", "pint" => "pints", "quart" => "quarts", "liter" => "liters",
                   "lb" => "lbs", "piece" => "pieces", "slice" => "slices", "clove" => "cloves",
                   "pinch" => "pinches", "dash" => "dashes" }.freeze

  # One of GroceryList::Breakdown#amounts as text: "3 ¼ cups", "450 g", "2".
  def grocery_amount(quantity, unit)
    number = FRACTION_UNITS.include?(unit) ? kitchen_number(quantity) : plain_number(quantity)
    unit_text = quantity > 1 ? PLURAL_UNITS.fetch(unit, unit) : unit
    [ number, unit_text ].compact.join(" ")
  end

  private

  # Whole number plus the nearest common fraction when it's close (¼ ⅓ ½ ⅔ ¾),
  # else one decimal place.
  def kitchen_number(quantity)
    whole = quantity.floor
    rest  = quantity - whole
    return whole.to_s if rest < 0.05
    return (whole + 1).to_s if rest > 0.95

    fraction, symbol = FRACTIONS.min_by { |value, _| (value - rest).abs }
    return plain_number(quantity) if (fraction - rest).abs > 0.05

    whole.zero? ? symbol : "#{whole} #{symbol}"
  end

  def plain_number(quantity)
    rounded = quantity >= 10 ? quantity.round : quantity.round(1)
    rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
  end
end
