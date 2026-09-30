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

  validates :ingredient, presence: true

  before_validation :capitalize_ingredient

  scope :for_household, ->(household) { where(household: household) }

  # The household's ingredient called `name`, whatever its capitalization,
  # or a new unsaved one to add to their library — for a name typed straight
  # into the recipe page's ingredient picker.
  def self.find_or_initialize_for(household, name, created_by:)
    name = name.to_s.squish
    household.ingredients.where("LOWER(ingredient) = ?", name.downcase).order(:id).first ||
      household.ingredients.build(ingredient: name, created_by:)
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

      tags.each { |tag| copy.tags << tag.mirror_for(user) } if user

      copy
    end
  end

  def capitalize_ingredient
    return if ingredient.blank?
    self.ingredient = ingredient.strip.capitalize
  end
end