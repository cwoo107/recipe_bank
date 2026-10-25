# A label for recipes (and ingredients) — "Breakfast", "Quick & Easy". Tags
# belong to the household, like its recipes, so everyone in it shares one
# set; user is just who made a tag (nil for the defaults).
class Tag < ApplicationRecord
  belongs_to :household
  belongs_to :user, optional: true

  has_many :recipe_tags,    dependent: :destroy
  has_many :recipes,        through: :recipe_tags
  has_many :ingredient_tags, dependent: :destroy
  has_many :ingredients,    through: :ingredient_tags

  # Every household starts with these (Household#seed_default_tags!); they
  # can be renamed, recolored or deleted like any other tag.
  DEFAULTS = [
    [ "Breakfast",      "#d4b157" ],
    [ "Lunch",          "#7a9d9d" ],
    [ "Dinner",         "#577584" ],
    [ "Dessert",        "#a67a7f" ],
    [ "Quick & Easy",   "#7a9d9d" ],
    [ "Healthy",        "#7a8f62" ],
    [ "Vegetarian",     "#7a8f62" ],
    [ "Gluten Free",    "#d4b157" ],
    [ "Comfort Food",   "#b5806a" ],
    [ "BBQ & Grilling", "#a67a7f" ]
  ].freeze

  validates :tag,   presence: true, uniqueness: { scope: :household_id, case_sensitive: false }
  validates :color, presence: true

  before_validation { self.tag = tag.to_s.strip }

  scope :ordered, -> { order(:tag) }

  # The household's tag by this name (any capitalization), or a new one — in
  # the next of the default colors — when it doesn't have one yet. For the
  # recipe page's tag picker, where a new name can be typed straight in.
  def self.find_or_create_for(household, name, user: nil)
    household.tags.where("LOWER(tag) = ?", name.strip.downcase).first ||
      household.tags.create!(tag: name, user: user,
                             color: DEFAULTS.map(&:last).uniq[household.tags.count % DEFAULTS.map(&:last).uniq.size])
  end

  # Copying a recipe into another household re-points its tags at that
  # household's tag of the same name, creating it if they don't have one.
  def mirror_for(other_household)
    return self if household_id == other_household.id

    other_household.tags.where("LOWER(tag) = ?", tag.downcase).first ||
      other_household.tags.create!(tag: tag, color: color)
  end
end
