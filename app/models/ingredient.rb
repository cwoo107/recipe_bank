class Ingredient < ApplicationRecord
  belongs_to :created_by, class_name: 'User', optional: true
  # Each household keeps its own ingredient library, so editing or deleting
  # an ingredient only ever touches that household's recipes. Ingredients
  # without a household are an unowned catalog (see products:import) that
  # imports can copy from but nobody edits in place.
  belongs_to :household, optional: true
  # The ingredient this one was copied from, when it came into the household
  # via a copied or imported recipe.
  belongs_to :source_ingredient, class_name: 'Ingredient', optional: true
  has_many :copies, class_name: 'Ingredient', foreign_key: :source_ingredient_id,
           dependent: :nullify, inverse_of: :source_ingredient

  has_one  :nutrition_fact, dependent: :destroy
  has_many :recipe_ingredients, dependent: :destroy
  has_many :recipes, through: :recipe_ingredients
  has_many :ingredient_tags, dependent: :destroy
  has_many :tags, through: :ingredient_tags
  has_many :grocery_lists, dependent: :destroy

  # Ingredient families (the "family" column) — the one list everything else
  # reads from: the family select, filter chips and tags (IngredientsHelper,
  # which adds each one's colors), the CSV catalog import, the week plan PDF's
  # grocery headings, and the AI classification prompts (IngredientAssistant),
  # which get each family's description. "grocery" is the catch-all.
  FAMILIES = {
    'protein'    => { label: 'Protein',         description: 'meat, poultry, fish, eggs, tofu, dried beans, legumes' },
    'produce'    => { label: 'Produce',         description: 'fresh fruits, vegetables, fresh herbs' },
    'dairy'      => { label: 'Dairy',           description: 'milk, cheese, yogurt, butter, cream' },
    'grain'      => { label: 'Grain',           description: 'bread, pasta, rice, flour, oats, cereal, tortillas' },
    'fat'        => { label: 'Fat',             description: 'cooking oils, lard, shortening, cooking spray' },
    'spices'     => { label: 'Spices',          description: 'dried herbs, spices, seasonings, salt, pepper' },
    'condiments' => { label: 'Condiments',      description: 'sauces, dressings, vinegars, ketchup, mustard, mayonnaise, soy sauce, salsa, hot sauce, honey, jams' },
    'canned'     => { label: 'Canned & Jarred', description: 'canned vegetables and tomatoes, tomato paste, canned beans, coconut milk, stock, broth' },
    'baking'     => { label: 'Baking',          description: 'sugar, baking soda, baking powder, yeast, cornstarch, cocoa, chocolate chips, extracts' },
    'nuts'       => { label: 'Nuts & Seeds',    description: 'nuts, seeds, nut butters, dried fruit' },
    'frozen'     => { label: 'Frozen',          description: 'frozen fruits and vegetables, frozen meals, ice cream' },
    'beverages'  => { label: 'Beverages',       description: 'coffee, tea, juice, soda, wine and beer' },
    'grocery'    => { label: 'Grocery',         description: 'anything that fits none of the above (snacks, packaged foods, paper goods)' }
  }.freeze

  # Ingredients recipes list but nobody buys — tap water. Left off grocery
  # lists (GroceryListsController#generate). Matched by name, any capitals.
  NOT_SHOPPED = %w[water].freeze

  def not_shopped? = NOT_SHOPPED.include?(ingredient.to_s.squish.downcase)

  def self.family_label(family)
    FAMILIES.dig(family.to_s.downcase, :label) || family.to_s.titleize
  end

  # Where a family falls in FAMILIES' order — lists of ingredients (a
  # recipe's, the shopping list) sort by it. Blank or unknown families last.
  def self.family_rank(family)
    FAMILIES.keys.index(family.to_s.downcase) || FAMILIES.size
  end

  # The same order in SQL, for ORDER BY.
  def self.family_order_sql
    whens = FAMILIES.keys.each_with_index.map { |key, index| "WHEN #{connection.quote(key)} THEN #{index}" }.join(" ")
    Arel.sql("CASE LOWER(ingredients.family) #{whens} ELSE #{FAMILIES.size} END")
  end

  def family_rank = self.class.family_rank(family)

  validates :ingredient, presence: true

  before_validation :capitalize_ingredient

  scope :for_household, ->(household) { where(household: household) }
  scope :named, ->(name) { where("LOWER(ingredients.ingredient) = ?", name.to_s.squish.downcase) }
  scope :catalog, -> { where(household_id: nil) }

  # For a name typed straight into the recipe page's ingredient picker,
  # whatever its capitalization: the household's own ingredient by that
  # name; else a copy of the shared catalog's (saved — prices, nutrition and
  # all, via #copy_for); else a new, unsaved one to add to their library.
  def self.find_or_initialize_for(household, name, created_by:)
    name = name.to_s.squish
    household.ingredients.named(name).order(:id).first ||
      catalog_entry_named(name)&.copy_for(household, user: created_by) ||
      household.ingredients.build(ingredient: name, created_by:)
  end

  # The catalog's ingredient by that name — the unbranded one if there are
  # several brands of it, since a typed name doesn't say which.
  def self.catalog_entry_named(name)
    catalog.named(name).order(Arel.sql("CASE WHEN COALESCE(ingredients.brand, '') = '' THEN 0 ELSE 1 END"), :id).first
  end

  # What the ingredient pickers (a recipe's, the grocery list's) offer a
  # household: its own ingredients, plus the catalog's it doesn't have yet —
  # by name, or as an earlier copy. Picking one of those copies it in (see
  # .pick_for). Favorites first, then A–Z.
  def self.pickable_for(household)
    own    = household.ingredients.to_a
    names  = own.map { |ingredient| ingredient.ingredient.to_s.downcase }.to_set
    copied = own.filter_map(&:source_ingredient_id).to_set
    extra  = catalog.reject { |entry| copied.include?(entry.id) || names.include?(entry.ingredient.to_s.downcase) }

    (own + extra).sort_by { |ingredient| [ ingredient.favorite? ? 0 : 1, ingredient.ingredient.to_s.downcase ] }
  end

  # The ingredient a picker's id stands for, in `household`'s library: one of
  # its own, or a catalog one copied in (saved). Nil for anything else — no
  # picking another household's ingredients.
  def self.pick_for(household, id, user:)
    return if id.blank?

    household.ingredients.find_by(id:) || catalog.find_by(id:)&.copy_for(household, user:)
  end

  # Anything IngredientEnrichmentJob would fill in still blank.
  def needs_enrichment?
    family.blank? || unit_price.blank? || unit_servings.blank? || nutrition_fact.nil?
  end

  def editable_by?(user)
    household_id.present? && household_id == user&.household&.id
  end

  # This ingredient as it exists in `household`'s library: itself if it's
  # already theirs, an earlier copy of it, or a same-named, same-brand
  # ingredient they already have — otherwise a fresh copy, carrying the
  # nutrition facts and (mirrored into `user`'s tags) the tags across.
  def copy_for(household, user: household.owner)
    return self if household_id == household.id

    household.ingredients.find_by(source_ingredient_id: id) ||
      household_equivalent(household) ||
      duplicate_into(household, user)
  end

  private

  def household_equivalent(household)
    household.ingredients
             .where('LOWER(ingredient) = ?', ingredient.to_s.strip.downcase)
             .detect { |candidate| candidate.brand.to_s.strip.casecmp?(brand.to_s.strip) }
  end

  def duplicate_into(household, user)
    transaction do
      copy = household.ingredients.create!(
        attributes.slice('ingredient', 'brand', 'family', 'organic', 'unit_price', 'unit_servings')
                  .merge(source_ingredient: self, created_by: user)
      )

      if nutrition_fact
        copy.create_nutrition_fact!(
          nutrition_fact.attributes.except('id', 'ingredient_id', 'created_at', 'updated_at')
        )
      end

      tags.each { |tag| copy.tags << tag.mirror_for(household) }

      copy
    end
  end

  def capitalize_ingredient
    return if ingredient.blank?
    self.ingredient = ingredient.strip.capitalize
  end
end