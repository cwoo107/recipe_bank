# An uploaded grocery receipt, read on Sidekiq (ProcessReceiptScanJob) and
# then held for the user to review: which lines are which ingredients, and
# whether to take the receipt's prices. Applying it checks those ingredients
# off the week's grocery list (week_of) and updates the prices they ticked.
class ReceiptScan < ApplicationRecord
  belongs_to :household
  belongs_to :user

  # Progress for the scan page, broadcast over Action Cable (Redis) from the
  # worker — best-effort, as for RecipeImportJob: a failed broadcast is
  # logged, and the page shows the real state on its next load.
  after_create_commit -> { broadcast_safely { broadcast_replace_to "receipt_scan_#{id}" } }
  after_update_commit -> { broadcast_safely { broadcast_replace_to "receipt_scan_#{id}" } }

  enum :status, {
    pending:               'pending',
    reading_receipt:       'reading_receipt',
    matching_items:        'matching_items',
    awaiting_confirmation: 'awaiting_confirmation',
    applied:               'applied',
    failed:                'failed'
  }

  # Prices within this of each other count as the same.
  PRICE_TOLERANCE = 0.01

  # One line of the receipt, and the ingredient it was matched to (if any).
  LineItem = Struct.new(
    :index, :text, :name, :quantity, :unit_price, :total_price, :by_weight,
    :ingredient, :on_list, :household_id,
    keyword_init: true
  ) do
    def matched? = ingredient.present?

    # What one of these cost, from the receipt — nil when it doesn't say.
    def price_each
      price = unit_price || (total_price / quantity if total_price && quantity.to_f.positive?)
      price&.to_f&.round(2)
    end

    # Only the household's own ingredients can be repriced (not a catalog
    # entry its list happens to use). Weighed items are priced per pound (or
    # kilo), which isn't what an ingredient's unit price means, so those
    # aren't offered either.
    def price_differs?
      return false unless matched? && ingredient.household_id == household_id && !by_weight && price_each

      ingredient.unit_price.nil? || (ingredient.unit_price.to_f - price_each).abs >= PRICE_TOLERANCE
    end
  end

  def week_range = week_of...(week_of + 7)

  # The week's grocery-list lines that are ingredients (notes can't be on a receipt).
  def week_grocery_lists
    household.grocery_lists.where(week_of: week_range).where.not(ingredient_id: nil)
  end

  # What a receipt line can be matched to: the household's own ingredients,
  # plus any other its grocery lists use.
  def matchable_ingredients
    Ingredient.for_household(household)
              .or(Ingredient.where(id: household.grocery_lists.where.not(ingredient_id: nil).select(:ingredient_id)))
  end

  # The receipt's lines, wrapped for display. `index` is the line's position,
  # which is what the review form posts back. Ingredients are re-looked up
  # within matchable_ingredients, so a match can't point anywhere else.
  def line_items
    rows = Array(items).select { |row| row.is_a?(Hash) }
    ingredients = matchable_ingredients.where(id: rows.filter_map { |row| row['ingredient_id'] }).index_by(&:id)
    on_list = week_grocery_lists.distinct.pluck(:ingredient_id).to_set

    rows.each_with_index.map do |row, index|
      ingredient = ingredients[row['ingredient_id']]
      LineItem.new(
        index:       index,
        text:        row['text'],
        name:        row['name'],
        quantity:    row['quantity'],
        unit_price:  row['unit_price'],
        total_price: row['total_price'],
        by_weight:   row['by_weight'] == true,
        ingredient:   ingredient,
        on_list:      ingredient.present? && on_list.include?(ingredient.id),
        household_id: household_id
      )
    end
  end

  # Atomically moves a scan from awaiting_confirmation to applied. Only one
  # caller can win, so a second submit (another tab, a resubmitted request)
  # doesn't apply the receipt twice.
  def claim_application!
    claimed = self.class.where(id: id, status: "awaiting_confirmation")
                        .update_all(status: "applied", updated_at: Time.current) == 1
    reload if claimed
    claimed
  end

  # Applies the user's review: the lines they kept (`confirmed` indexes) are
  # checked off the week's list, and of those, the ones they ticked in
  # `price_updates` set the ingredient's unit price. Returns how many list
  # lines were checked off and how many prices changed.
  def apply!(confirmed:, price_updates:)
    confirmed     = to_index_set(confirmed)
    price_updates = to_index_set(price_updates) & confirmed
    kept = line_items.select { |item| item.matched? && confirmed.include?(item.index) }

    transaction do
      checked = week_grocery_lists.where(ingredient_id: kept.map { |item| item.ingredient.id }, checked: [ false, nil ])
                                  .update_all(checked: true, updated_at: Time.current)

      priced = kept.select { |item| price_updates.include?(item.index) && item.price_differs? }
      # One price per ingredient — the last line wins if it was bought twice.
      priced.index_by { |item| item.ingredient.id }.each_value do |item|
        item.ingredient.update!(unit_price: item.price_each)
      end

      { checked: checked, prices: priced.map { |item| item.ingredient.id }.uniq.size }
    end
  end

  private

  # filter_map over to_i: a blank or junk value must not coerce to 0 and
  # silently pick the first line.
  def to_index_set(values)
    Array(values).filter_map { |i| Integer(i, exception: false) }.to_set
  end

  def broadcast_safely
    yield
  rescue => e
    Rails.logger.error "ReceiptScan ##{id}: progress broadcast failed (#{e.class}: #{e.message}) — " \
                       "the page shows the real state on reload"
  end
end
