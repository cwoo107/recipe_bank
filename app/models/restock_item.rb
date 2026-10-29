class RestockItem < ApplicationRecord
  belongs_to :user
  belongs_to :household
  belongs_to :restock_category

  has_many :restock_item_stores, dependent: :destroy
  has_many :stores, -> { ordered }, through: :restock_item_stores
  # Grocery ingredients that are the same thing (RestockItemIngredient).
  has_many :restock_item_ingredients, dependent: :destroy

  acts_as_list scope: :restock_category_id

  after_save :apply_store_names, if: -> { @store_names }

  validates :name, presence: true

  scope :ordered, -> { order(:position) }

  # The restock shopping list: everything marked Restock, grouped by store —
  # items at no store last, as "Any store" — then by restock category in
  # checklist order. Returns [[store_name, [[category, items]]]].
  #
  # Each item is listed once. One bought at several stores goes under
  # whichever of them has the most on the list (counting every item that can
  # be bought there), so it joins the bigger trip: with 5 things from Amazon
  # and 1 from Target, an item at both goes on the Amazon list. Ties go to
  # the store that comes first alphabetically.
  def self.shopping_list(household)
    items = household.restock_items.where(restock: true).includes(:restock_category, :stores).to_a

    counts = items.flat_map(&:stores).tally
    by_store = Hash.new { |hash, key| hash[key] = [] }
    items.each do |item|
      store = item.stores.min_by { |s| [ -counts[s], s.name.downcase ] }
      by_store[store&.name] << item
    end

    by_store.sort_by { |name, _| [ name.nil? ? 1 : 0, name.to_s.downcase ] }.map do |name, store_items|
      categories = store_items.group_by(&:restock_category)
                              .sort_by { |category, _| [ category.position, category.name ] }
                              .map { |category, category_items| [ category, category_items.sort_by(&:position) ] }
      [ name || "Any store", categories ]
    end
  end

  # The form's store picker sends the item's whole set of stores by name
  # ("Costco, Target"); names the household doesn't have yet become new stores.
  def store_name_list = @store_names || stores.map(&:name)
  def store_names     = store_name_list.join(", ")

  def store_names=(names)
    @store_names = names.to_s.split(",").map(&:strip).compact_blank.uniq(&:downcase)
  end

  # Drag-and-drop move between lists. Mirrors Todo#move_to_column!.
  def move_to_list!(new_restock_category_id, new_position = nil)
    new_restock_category_id = new_restock_category_id.to_i
    return if new_restock_category_id == restock_category_id && (new_position.nil? || new_position == position)

    old_restock_category_id  = restock_category_id
    self.restock_category_id = new_restock_category_id
    remove_from_list if old_restock_category_id != new_restock_category_id

    if new_position
      insert_at(new_position.to_i)
    else
      move_to_bottom
    end

    save!
  end

  # restocked: true when it's ticked off the restock shopping list (bought) —
  # that's what dates last_restocked. A check-in on the card doesn't.
  def mark_stocked!(restocked: false)
    attributes = { stocked: true, restock: false, last_date_checked_stocked: Time.current }
    attributes[:last_restocked] = Date.current if restocked
    update!(attributes)
  end

  # last_restocked: puts back the date an untick on the shopping list is
  # undoing (see RestockItemsController#mark_restock).
  def mark_restock!(**last_restocked)
    update!(restock: true, stocked: false, last_date_checked_restocked: Time.current, **last_restocked.slice(:last_restocked))
  end

  # Ticked off the restock shopping list today — what unticking its grocery
  # line can put back (RestockItemIngredient.sync_from_groceries).
  def bought_today?
    stocked? && last_restocked == Date.current
  end

  # Still on the restock shopping list, or ticked off it this week — when a
  # linked grocery line says "also on restock list".
  def on_shopping_list?
    restock? || (stocked? && last_restocked.present? && last_restocked >= Date.current.beginning_of_week)
  end

  # The grocery lines for the week starting `week_start` that are this item
  # under another name (a linked ingredient) — its "also on grocery list".
  def grocery_lines(week_start)
    household.grocery_lists.where(week_of: week_start...(week_start + 7))
             .where(ingredient_id: restock_item_ingredients.linked.select(:ingredient_id))
  end

  # A badge only shows while the check that produced it is still fresh (this
  # calendar week) — an old "Stocked" check shouldn't keep glowing green
  # forever, and re-checking is what clears or refreshes it.
  def stocked_badge?
    stocked? && within_current_week?(last_date_checked_stocked)
  end

  def restock_badge?
    restock? && within_current_week?(last_date_checked_restocked)
  end

  # True once either check-in has happened this week — used to hide the
  # quick check-in buttons on the card (they stay available in the edit form).
  def checked_this_week?
    stocked_badge? || restock_badge?
  end

  private

  def apply_store_names
    names = @store_names
    @store_names = nil
    self.stores = names.map do |name|
      household.stores.where("LOWER(name) = ?", name.downcase).first || household.stores.create!(name: name)
    end
  end

  def within_current_week?(timestamp)
    return false if timestamp.blank?
    (Date.current.beginning_of_week..Date.current.end_of_week).cover?(timestamp.to_date)
  end
end
