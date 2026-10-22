class GroceryList < ApplicationRecord
  # No ingredient means a note (see #note_only?).
  belongs_to :ingredient, optional: true
  belongs_to :user
  belongs_to :household

  serialize :meal_ids, type: Array, coder: JSON

  validates :note, length: { maximum: 100 }
  validate  :ingredient_or_note

  # A line that's just a reminder — "birthday candles", "check for foil" —
  # rather than an ingredient: no units or price, and regenerating the list
  # from the meal plan leaves it alone.
  def note_only? = ingredient_id.nil?

  def title = note_only? ? note : ingredient.ingredient

  def meals
    Meal.where(id: meal_ids)
  end

  # The recipes this line is for and how much they need (the "used in N
  # meals" hover). Pass Breakdown.uses_by_ingredient for the whole list to
  # save working it out row by row.
  def breakdown(uses_by_ingredient = nil)
    return Breakdown.new([]) if note_only?

    uses_by_ingredient ||= Breakdown.uses_by_ingredient(meals.includes(:recipe))
    Breakdown.new(uses_by_ingredient.fetch(ingredient_id, []).select { |use| meal_ids.include?(use.meal_id) })
  end

  private

  def ingredient_or_note
    errors.add(:base, "Pick an ingredient or write a note") if ingredient.nil? && note.blank?
  end
end
