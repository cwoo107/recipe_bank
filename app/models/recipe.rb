class Recipe < ApplicationRecord
  belongs_to :user
  has_many :recipe_ingredients, dependent: :destroy
  has_many :ingredients, through: :recipe_ingredients
  has_many :recipe_tags, dependent: :destroy
  has_many :tags, through: :recipe_tags
  has_many :steps, -> { order(position: :asc) }, dependent: :destroy
  has_many :meals
  has_many :user_favorites, dependent: :destroy
  has_many :favorited_by, through: :user_favorites, source: :user
  has_many :collection_recipes
  has_many :collections, through: :collection_recipes

  VISIBILITY = %w[public private].freeze

  validates :title,      presence: true
  validates :visibility, inclusion: { in: VISIBILITY }
  validates :servings,   numericality: { greater_than: 0 }, allow_nil: true

  scope :publicly_visible, -> { where(visibility: 'public') }
  scope :visible_to, ->(user) {
    where(visibility: 'public').or(where(user: user))
  }
  # Sort favorites-first for a given user without a subquery per row.
  # Usage: Recipe.visible_to(user).by_favorite_for(user)
  scope :by_favorite_for, ->(user) {
    joins(
      <<~SQL
        LEFT JOIN user_favorites uf_sort
          ON uf_sort.recipe_id = recipes.id
         AND uf_sort.user_id = #{user.id.to_i}
      SQL
    ).order(Arel.sql('uf_sort.id IS NULL ASC, recipes.title ASC'))
  }

  def owned_by?(user)
    self.user_id == user&.id
  end

  def public?  = visibility == 'public'
  def private? = visibility == 'private'

  # ── Macros ────────────────────────────────────────────────────────────────

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
                     'oklch(71.1% 0.019 323.02)',
                     'oklch(85% 0.08 95)',
                     'oklch(75% 0.06 45)'
                   ],
                   borderWidth: 2
                 }]
    }
  end

  private

  def calculate_macro_for_ingredient(recipe_ingredient, macro_field)
    ingredient     = recipe_ingredient.ingredient
    nutrition_fact = ingredient.nutrition_fact
    return 0 unless nutrition_fact

    macro_per_serving  = nutrition_fact.send(macro_field) || 0
    serving_size_grams = convert_to_grams(nutrition_fact.serving_size, nutrition_fact.serving_unit)
    return 0 if serving_size_grams.zero?

    ingredient_grams = convert_to_grams(recipe_ingredient.quantity, recipe_ingredient.unit)
    (ingredient_grams / serving_size_grams) * macro_per_serving
  end

  def convert_to_grams(quantity, unit)
    return 0 if quantity.nil? || unit.nil?
    unit = unit.downcase.strip
    return quantity if ['g', 'gram', 'grams'].include?(unit)

    case unit
    when 'ml', 'milliliter', 'milliliters'       then quantity
    when 'cup', 'cups'                            then quantity * 240
    when 'tbsp', 'tablespoon', 'tablespoons'      then quantity * 15
    when 'tsp', 'teaspoon', 'teaspoons'           then quantity * 5
    when 'oz', 'ounce', 'ounces'                  then quantity * 28.35
    when 'lb', 'lbs', 'pound', 'pounds'           then quantity * 453.592
    when 'kg', 'kilogram', 'kilograms'            then quantity * 1000
    when 'whole', 'piece', 'pieces', 'item', 'items' then quantity * 100
    when 'clove', 'cloves'                        then quantity * 3
    when 'slice', 'slices'                        then quantity * 30
    when 'strip', 'strips'                        then quantity * 8
    else quantity
    end
  end
end