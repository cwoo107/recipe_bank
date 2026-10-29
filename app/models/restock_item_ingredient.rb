# A household's answer to "is this grocery ingredient the same thing as this
# restock item?" — linked: true for yes, false for no. A linked pair shows on
# both lists ("also on restock list" / "also on grocery list") and ticking one
# off ticks off the other. Either answer means the pair isn't suggested again
# (see RestockMatch).
class RestockItemIngredient < ApplicationRecord
  belongs_to :restock_item
  belongs_to :ingredient

  validates :ingredient_id, uniqueness: { scope: :restock_item_id }

  scope :linked, -> { where(linked: true) }
  scope :for_household, ->(household) { joins(:restock_item).where(restock_items: { household_id: household.id }) }

  # The household's restock items linked to each of `ingredient_ids`:
  # { ingredient_id => [restock items] }.
  def self.restock_items_by_ingredient(household, ingredient_ids)
    links = linked.joins(:restock_item)
                  .where(ingredient_id: ingredient_ids, restock_items: { household_id: household.id })
                  .includes(:restock_item)
    links.group_by(&:ingredient_id).transform_values { |rows| rows.map(&:restock_item) }
  end

  # Ingredients linked to a restock item that's marked Stocked — already in
  # the house, so generating the grocery list leaves them off.
  def self.stocked_ingredient_ids(household)
    linked.joins(:restock_item)
          .where(restock_items: { household_id: household.id, stocked: true })
          .distinct.pluck(:ingredient_id).to_set
  end

  # The grocery lines for the week starting `week_start` linked to each of
  # `restock_items`: { restock_item_id => [grocery lines] }.
  def self.grocery_lines_by_restock_item(household, restock_items, week_start)
    pairs = linked.where(restock_item_id: restock_items.map(&:id)).pluck(:restock_item_id, :ingredient_id)
    return {} if pairs.empty?

    lines = household.grocery_lists.where(week_of: week_start...(week_start + 7), ingredient_id: pairs.map(&:last))
                     .group_by(&:ingredient_id)
    pairs.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(item_id, ingredient_id), by_item|
      by_item[item_id].concat(lines.fetch(ingredient_id, []))
    end
  end

  # Grocery lines ticked (or unticked) — on the list itself, by "Select all"
  # or by a receipt — tick off (or put back) the restock items linked to them.
  # Ticking only touches items still waiting on the restock list; unticking
  # only puts back what was bought today, so it can't undo an older purchase.
  # Returns the restock items it changed.
  def self.sync_from_groceries(household, ingredient_ids, checked:)
    items = restock_items_by_ingredient(household, ingredient_ids).values.flatten.uniq
    items = items.select { |item| checked ? item.restock? : item.bought_today? }
    items.each { |item| checked ? item.mark_stocked!(restocked: true) : item.mark_restock! }
    items
  end
end
