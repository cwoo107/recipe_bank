# One recipe used as an ingredient of another: the lemon garlic sauce that a
# chicken recipe calls for. It's a live reference, not a copy — editing the
# sauce changes every recipe built on it.
class RecipeComponent < ApplicationRecord
  belongs_to :parent_recipe,    class_name: "Recipe", inverse_of: :recipe_components
  belongs_to :component_recipe, class_name: "Recipe", inverse_of: :component_usages

  # How many batches of the component the parent calls for. Multiplies down
  # the chain, so half a sauce needs half of everything the sauce needs.
  validates :multiplier, numericality: { greater_than: 0 }
  validates :component_recipe_id, uniqueness: {
    scope: :parent_recipe_id, message: "is already part of this recipe"
  }
  validate :must_not_be_its_own_component
  validate :must_not_close_a_loop

  before_validation :set_position, on: :create

  private

  def set_position
    return unless parent_recipe

    self.position ||= parent_recipe.recipe_components.maximum(:position).to_i + 1
    # Shares one sequence with the parent's own steps — see Recipe#instruction_items.
    self.instruction_position ||= parent_recipe.next_instruction_position
  end

  def must_not_be_its_own_component
    return if component_recipe_id.blank?

    errors.add(:component_recipe, "can't be the recipe itself") if component_recipe_id == parent_recipe_id
  end

  # A sauce can't call for the chicken that calls for it — resolving either
  # one would never terminate.
  def must_not_close_a_loop
    return if component_recipe.blank? || parent_recipe.blank?
    return if component_recipe_id == parent_recipe_id # already reported above

    if component_recipe.depends_on?(parent_recipe)
      errors.add(:component_recipe, "already uses this recipe, so adding it would be circular")
    end
  end
end
