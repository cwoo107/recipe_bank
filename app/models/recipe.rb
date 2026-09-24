class Recipe < ApplicationRecord
  belongs_to :user
  # Set when this recipe was saved out of the public browse list. Keeps the
  # link back to the original so we can tell "already saved" from "not yet".
  belongs_to :source_recipe, class_name: 'Recipe', optional: true
  has_many :copies, class_name: 'Recipe', foreign_key: :source_recipe_id,
           dependent: :nullify, inverse_of: :source_recipe
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

  # Recipes used as ingredients of this one (the sauce on the chicken), and
  # the reverse — every recipe built on this one.
  has_many :recipe_components, -> { order(:instruction_position, :position) },
           foreign_key: :parent_recipe_id, dependent: :destroy, inverse_of: :parent_recipe
  has_many :component_recipes, through: :recipe_components, source: :component_recipe

  has_many :component_usages, class_name: "RecipeComponent",
           foreign_key: :component_recipe_id, dependent: :destroy, inverse_of: :component_recipe
  has_many :used_by_recipes, through: :component_usages, source: :parent_recipe

  VISIBILITY = %w[public private].freeze

  COPY_SUFFIX = / \(copy(?: \d+)?\)\z/

  validates :title,      presence: true
  validates :visibility, inclusion: { in: VISIBILITY }
  validates :servings,   numericality: { greater_than: 0 }, allow_nil: true

  scope :publicly_visible, -> { where(visibility: 'public') }
  scope :visible_to, ->(user) {
    where(visibility: 'public').or(where(user: user))
  }

  # Recipes belong to individual users, but a household shares them: anything
  # any member wrote (or saved) is "our recipes".
  scope :for_household, ->(household) {
    where(user_id: household_user_ids(household))
  }

  # The browse pool — public recipes the household hasn't written itself.
  scope :public_beyond_household, ->(household) {
    publicly_visible.where.not(user_id: household_user_ids(household))
  }

  # Everything a member of `household` is allowed to open: their household's
  # recipes plus anything shared publicly.
  scope :browsable_by_household, ->(household) {
    where(user_id: household_user_ids(household)).or(where(visibility: 'public'))
  }

  def self.household_user_ids(household)
    household ? household.users.select(:id) : []
  end

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

  def owned_by_household?(household)
    household.present? && household.users.exists?(id: user_id)
  end

  # A free name for a variant of this recipe in `user`'s collection:
  # "Teriyaki Bowls" → "Teriyaki Bowls (copy)", then "(copy 2)", "(copy 3)".
  # Copying a copy re-uses the original stem rather than stacking suffixes.
  def copy_title_for(user)
    base  = title.to_s.sub(COPY_SUFFIX, "")
    taken = user.recipes.pluck(:title).to_set

    candidate = "#{base} (copy)"
    counter   = 2
    while taken.include?(candidate)
      candidate = "#{base} (copy #{counter})"
      counter  += 1
    end

    candidate
  end

  # Deep-copies the recipe into `user`'s collection: ingredients are shared
  # records so they're just re-pointed, steps carry their rich text over, and
  # tags are mirrored into the saving user's own tag list (tags are personal).
  # The copy starts private — it's theirs to share or not.
  def duplicate_for(user, title: self.title)
    copy = Recipe.new(
      user:           user,
      source_recipe:  self,
      title:          title,
      description:    description,
      servings:       servings,
      visibility:     'private'
    )

    transaction do
      copy.save!

      recipe_ingredients.each do |ri|
        copy.recipe_ingredients.create!(ingredient_id: ri.ingredient_id, quantity: ri.quantity, unit: ri.unit)
      end

      steps.each do |step|
        copy.steps.create!(position: step.position, content: step.content&.body)
      end

      tags.each { |tag| copy.tags << tag.mirror_for(user) }

      recipe_components.each do |component|
        copy.recipe_components.create!(component_recipe_id: component.component_recipe_id,
                                       multiplier: component.multiplier,
                                       position: component.position)
      end
    end

    copy
  end

  # ── Components ────────────────────────────────────────────────────────────

  # One recipe's contribution to another: which recipe, and how much of a
  # batch of it is called for once the whole chain is multiplied out.
  Section = Struct.new(:recipe, :multiplier, :depth, :component, keyword_init: true) do
    # The recipe this one hangs off, and whether that's the page we're on —
    # only a direct component can be adjusted or removed from here.
    def via = component&.parent_recipe
    def directly_on?(other) = component&.parent_recipe_id == other&.id

    def own_ingredients
      recipe.recipe_ingredients.map { |ri| ScaledIngredient.new(recipe_ingredient: ri, multiplier: multiplier) }
    end

    def own_steps = recipe.steps.to_a
    def root?     = depth.zero?
    def any?      = recipe.recipe_ingredients.any? || recipe.steps.any?
  end

  # A recipe line seen through a chain of component multipliers. Quantity is
  # the only thing that changes — it's still the component's own line.
  ScaledIngredient = Struct.new(:recipe_ingredient, :multiplier, keyword_init: true) do
    def ingredient    = recipe_ingredient.ingredient
    def ingredient_id = recipe_ingredient.ingredient_id
    def unit          = recipe_ingredient.unit
    def quantity      = recipe_ingredient.quantity.to_f * multiplier
    def scaled?       = multiplier != 1.0
  end

  # This recipe followed by everything it pulls in, depth-first, with each
  # one's multiplier already folded in. `seen` guards against a loop in
  # existing data — RecipeComponent rejects new ones, but resolving must
  # terminate regardless of what's already in the table.
  def sections(multiplier: 1.0, depth: 0, seen: Set.new, component: nil)
    return [] if seen.include?(id)

    seen = seen + [id]
    own  = Section.new(recipe: self, multiplier: multiplier, depth: depth, component: component)

    own_and_nested = recipe_components.includes(:component_recipe).flat_map do |nested|
      nested.component_recipe.sections(
        multiplier: multiplier * nested.multiplier.to_f,
        depth:      depth + 1,
        seen:       seen,
        component:  nested
      )
    end

    [own] + own_and_nested
  end

  # Every ingredient line this recipe needs, its own and its components',
  # scaled. This is what nutrition, grocery lists and meal costs count.
  def all_ingredients
    sections.flat_map(&:own_ingredients)
  end

  def components? = recipe_components.any?

  # The instruction list: this recipe's own steps and its component recipes,
  # in one order the user controls by dragging. A component sits in the list
  # as a single entry that expands to its own sub-steps.
  def instruction_items
    items = steps.to_a + recipe_components.includes(:component_recipe).to_a

    items.sort_by do |item|
      [item.instruction_position || Float::INFINITY, item.class.name, item.id || 0]
    end
  end

  def next_instruction_position
    [steps.maximum(:instruction_position),
     recipe_components.maximum(:instruction_position)].compact.max.to_i + 1
  end

  # Is `other` anywhere in this recipe's component tree? Used to reject a
  # component that would close a loop.
  def depends_on?(other, seen = Set.new)
    return false if other.blank? || seen.include?(id)

    seen << id
    recipe_components.includes(:component_recipe).any? do |component|
      component.component_recipe_id == other.id ||
        component.component_recipe.depends_on?(other, seen)
    end
  end

  # ── Macros ────────────────────────────────────────────────────────────────

  def total_protein
    all_ingredients.sum { |line| calculate_macro_for_ingredient(line, :protein) }
  end

  def total_carbs
    all_ingredients.sum { |line| calculate_macro_for_ingredient(line, :total_carb) }
  end

  def total_fat
    all_ingredients.sum { |line| calculate_macro_for_ingredient(line, :total_fat) }
  end

  def total_calories
    all_ingredients.sum { |line| calculate_macro_for_ingredient(line, :calories) }
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

  # `line` is a ScaledIngredient — its quantity already carries the component
  # multipliers, so nothing here needs to know how deep it came from.
  def calculate_macro_for_ingredient(line, macro_field)
    ingredient     = line.ingredient
    nutrition_fact = ingredient&.nutrition_fact
    return 0 unless nutrition_fact

    macro_per_serving  = nutrition_fact.send(macro_field) || 0
    serving_size_grams = convert_to_grams(nutrition_fact.serving_size, nutrition_fact.serving_unit)
    return 0 if serving_size_grams.zero?

    ingredient_grams = convert_to_grams(line.quantity, line.unit)
    (ingredient_grams / serving_size_grams) * macro_per_serving
  end

  PIECE_GRAMS = 100

  def convert_to_grams(quantity, unit)
    return 0 if quantity.nil?
    # No unit means a count — "1 chicken breast", "2 eggs" — so weigh it the
    # same as an explicit "piece" rather than contributing nothing.
    return quantity * PIECE_GRAMS if unit.blank?

    unit = unit.downcase.strip
    return quantity if ['g', 'gram', 'grams'].include?(unit)

    case unit
    when 'ml', 'milliliter', 'milliliters'       then quantity
    when 'l', 'liter', 'liters'                   then quantity * 1000
    when 'cup', 'cups'                            then quantity * 240
    when 'pint', 'pints', 'pt'                    then quantity * 473
    when 'quart', 'quarts', 'qt'                  then quantity * 946
    when 'gallon', 'gallons', 'gal'               then quantity * 3785
    when 'fl oz', 'fluid ounce', 'fluid ounces'   then quantity * 30
    when 'tbsp', 'tablespoon', 'tablespoons'      then quantity * 15
    when 'tsp', 'teaspoon', 'teaspoons'           then quantity * 5
    when 'oz', 'ounce', 'ounces'                  then quantity * 28.35
    when 'lb', 'lbs', 'pound', 'pounds'           then quantity * 453.592
    when 'kg', 'kilogram', 'kilograms'            then quantity * 1000
    when 'whole', 'piece', 'pieces', 'item', 'items' then quantity * PIECE_GRAMS
    when 'clove', 'cloves'                        then quantity * 3
    when 'slice', 'slices'                        then quantity * 30
    when 'strip', 'strips'                        then quantity * 8
    when 'pinch', 'pinches'                       then quantity * 0.36
    when 'dash', 'dashes'                         then quantity * 0.6
    else quantity
    end
  end
end