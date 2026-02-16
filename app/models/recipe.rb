class Recipe < ApplicationRecord
  has_many :recipe_ingredients, dependent: :destroy
  has_many :ingredients, through: :recipe_ingredients
  has_many :recipe_tags, dependent: :destroy
  has_many :tags, through: :recipe_tags
  has_many :steps, -> { order(position: :asc) }, dependent: :destroy
  has_many :meals

  validates :title, presence: true
  validates :servings, numericality: { greater_than: 0 }, allow_nil: true

  # default_scope { order(favorite: :desc) }

  # Calculate total macros for the entire recipe
  def total_protein
    recipe_ingredients.includes(ingredient: :nutrition_fact).sum do |ri|
      calculate_macro_for_ingredient(ri, :protein)
    end
  end

  def total_carbs
    recipe_ingredients.includes(ingredient: :nutrition_fact).sum do |ri|
      calculate_macro_for_ingredient(ri, :total_carb)
    end
  end

  def total_fat
    recipe_ingredients.includes(ingredient: :nutrition_fact).sum do |ri|
      calculate_macro_for_ingredient(ri, :total_fat)
    end
  end

  def total_calories
    recipe_ingredients.includes(ingredient: :nutrition_fact).sum do |ri|
      calculate_macro_for_ingredient(ri, :calories)
    end
  end

  # Calculate macros per serving
  def protein_per_serving
    return 0 if servings.nil? || servings.zero?
    (total_protein / servings).round(1)
  end

  def carbs_per_serving
    return 0 if servings.nil? || servings.zero?
    (total_carbs / servings).round(1)
  end

  def fat_per_serving
    return 0 if servings.nil? || servings.zero?
    (total_fat / servings).round(1)
  end

  def calories_per_serving
    return 0 if servings.nil? || servings.zero?
    (total_calories / servings).round(0)
  end

  # Data formatted for Chart.js
  def macros_chart_data
    {
      labels: [
        "Protein: #{protein_per_serving}g",
        "Carbs: #{carbs_per_serving}g",
        "Fat: #{fat_per_serving}g"
      ],
      datasets: [{
                   label: 'Macros per Serving (g)',
                   data: [protein_per_serving, carbs_per_serving, fat_per_serving],
                   backgroundColor: [
                     'oklch(71.1% 0.019 323.02)',  # Mauve for protein
                     'oklch(85% 0.08 95)',     # Mist for carbs
                     'oklch(75% 0.06 45)'                      # Sage for fat
                   ],
                   borderWidth: 2
                 }]
    }

  end

  private

  # Convert ingredient quantity to grams and calculate macro
  def calculate_macro_for_ingredient(recipe_ingredient, macro_field)
    ingredient = recipe_ingredient.ingredient
    nutrition_fact = ingredient.nutrition_fact

    return 0 unless nutrition_fact

    # Get the macro value per serving from nutrition facts
    macro_per_serving = nutrition_fact.send(macro_field) || 0

    # Get nutrition fact serving size in grams
    serving_size_grams = convert_to_grams(
      nutrition_fact.serving_size,
      nutrition_fact.serving_unit
    )

    return 0 if serving_size_grams.zero?

    # Get recipe ingredient quantity in grams
    ingredient_grams = convert_to_grams(
      recipe_ingredient.quantity,
      recipe_ingredient.unit
    )

    # Calculate: (ingredient_grams / serving_size_grams) * macro_per_serving
    (ingredient_grams / serving_size_grams) * macro_per_serving
  end

  # Convert various units to grams
  def convert_to_grams(quantity, unit)
    return 0 if quantity.nil? || unit.nil?

    unit = unit.downcase.strip

    # Already in grams
    return quantity if ['g', 'gram', 'grams'].include?(unit)

    # Volume to weight conversions (approximations for common ingredients)
    case unit
    when 'ml', 'milliliter', 'milliliters'
      quantity # 1 ml ≈ 1 g for water-based liquids
    when 'cup', 'cups'
      quantity * 240 # 1 cup ≈ 240g
    when 'tbsp', 'tablespoon', 'tablespoons'
      quantity * 15 # 1 tbsp ≈ 15g
    when 'tsp', 'teaspoon', 'teaspoons'
      quantity * 5 # 1 tsp ≈ 5g
    when 'oz', 'ounce', 'ounces'
      quantity * 28.35 # 1 oz = 28.35g
    when 'lb', 'lbs', 'pound', 'pounds'
      quantity * 453.592 # 1 lb = 453.592g
    when 'kg', 'kilogram', 'kilograms'
      quantity * 1000 # 1 kg = 1000g
      # Count-based (rough estimates)
    when 'whole', 'piece', 'pieces', 'item', 'items'
      quantity * 100 # Assume 100g per item (very rough)
    when 'clove', 'cloves' # garlic
      quantity * 3 # 1 clove ≈ 3g
    when 'slice', 'slices'
      quantity * 30 # 1 slice ≈ 30g
    when 'strip', 'strips' # bacon
      quantity * 8 # 1 strip bacon ≈ 8g
    else
      # If unknown unit, treat as grams
      quantity
    end
  end
end