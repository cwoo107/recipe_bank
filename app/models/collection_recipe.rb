class CollectionRecipe < ApplicationRecord
  belongs_to :collection
  belongs_to :recipe

  validates :recipe_id, uniqueness: { scope: :collection_id }
end
