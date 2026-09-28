class RestockItem < ApplicationRecord
  belongs_to :user
  belongs_to :household
  belongs_to :restock_category

  acts_as_list scope: :restock_category_id

  validates :name, presence: true

  scope :ordered, -> { order(:position) }

  # The restock shopping list: everything marked Restock, grouped by the store
  # it's bought at (blank store last, as "Any store"), then by restock
  # category in checklist order. Returns [[store_name, [[category, items]]]].
  def self.shopping_list(household)
    items = household.restock_items.where(restock: true).includes(:restock_category).to_a

    by_store = items.group_by { |item| item.store.to_s.strip.downcase }
    by_store.sort_by { |key, _| [ key.blank? ? 1 : 0, key ] }.map do |key, store_items|
      name = key.blank? ? "Any store" : store_items.first.store.strip
      categories = store_items.group_by(&:restock_category)
                              .sort_by { |category, _| [ category.position, category.name ] }
                              .map { |category, category_items| [ category, category_items.sort_by(&:position) ] }
      [ name, categories ]
    end
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

  def mark_stocked!
    update!(stocked: true, restock: false, last_date_checked_stocked: Time.current)
  end

  def mark_restock!
    update!(restock: true, stocked: false, last_date_checked_restocked: Time.current)
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

  def within_current_week?(timestamp)
    return false if timestamp.blank?
    (Date.current.beginning_of_week..Date.current.end_of_week).cover?(timestamp.to_date)
  end
end
