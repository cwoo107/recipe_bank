class User < ApplicationRecord
  include HouseholdAccountable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :recipes,            dependent: :destroy
  has_many :tags,                dependent: :destroy
  has_many :recipe_import_jobs, dependent: :destroy
  has_many :collections,        dependent: :destroy
  has_many :created_ingredients, class_name: 'Ingredient',
                                  foreign_key: :created_by_id,
                                  dependent: :nullify

  # Household owns these now (see Household#meals etc. below) — removing a
  # household member must not wipe shared data they created, so no
  # dependent: :destroy here. Kept for "created by me" style queries.
  has_many :meals
  has_many :todos
  has_many :grocery_lists
  has_many :calendar_sources
  has_many :calendar_events

  has_many :user_favorites, dependent: :destroy
  has_many :favorited_recipes, through: :user_favorites, source: :recipe

  # Sub-users created via Household#invite_member get a membership instead
  # (set right after this record saves) — skip provisioning an owned
  # household for them.
  attribute :skip_household_provisioning, :boolean, default: false

  # Collected on the sign-up form so a new owner can name their household
  # instead of getting the generic default. Not a column — never persisted.
  attribute :household_family_name, :string

  after_create :provision_household, unless: :skip_household_provisioning

  def favorited?(recipe)
    user_favorites.exists?(recipe: recipe)
  end

  private

  # Every user needs a household to use the household-scoped planning
  # features. Sub-users created via Household#invite_member already get a
  # membership (not an owned household), so this is a no-op for them.
  def provision_household
    return if household.present?

    create_owned_household!(family_name: household_family_name.presence || Household.default_family_name_for(self))
  end
end
