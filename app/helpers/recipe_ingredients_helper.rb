module RecipeIngredientsHelper
  UNIT_ABBREVIATIONS = {
    'tablespoon' => 'tbsp',
    'tablespoons' => 'tbsp',
    'teaspoon' => 'tsp',
    'teaspoons' => 'tsp',
    'cup' => 'cup',
    'cups' => 'cups',
    'ounce' => 'oz',
    'ounces' => 'oz',
    'pound' => 'lb',
    'pounds' => 'lbs',
    'gram' => 'g',
    'grams' => 'g',
    'kilogram' => 'kg',
    'kilograms' => 'kg',
    'milliliter' => 'ml',
    'milliliters' => 'ml',
    'liter' => 'l',
    'liters' => 'l',
    'pint' => 'pt',
    'pints' => 'pts',
    'quart' => 'qt',
    'quarts' => 'qts',
    'gallon' => 'gal',
    'gallons' => 'gals',
    'pinch' => 'pinch',
    'dash' => 'dash',
    'clove' => 'clove',
    'cloves' => 'cloves',
    'slice' => 'slice',
    'slices' => 'slices',
    'piece' => 'piece',
    'pieces' => 'pieces'
  }.freeze

  def display_unit(unit)
    return '' if unit.blank?

    normalized = unit.to_s.downcase.strip
    UNIT_ABBREVIATIONS[normalized] || unit
  end

  def display_quantity_with_unit(quantity, unit)
    return '' if quantity.blank?

    formatted_quantity = if quantity == quantity.to_i
                           quantity.to_i.to_s
                         else
                           # Format to remove trailing zeros
                           quantity.to_f.to_s.sub(/\.?0+$/, '')
                         end

    unit_display = display_unit(unit)

    if unit_display.present?
      "#{formatted_quantity} #{unit_display}"
    else
      formatted_quantity
    end
  end
end
