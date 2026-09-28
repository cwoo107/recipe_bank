module Dashboard
  # The restock checklist: go through the household's staples, marking each
  # Stocked or Restock. Sits between meals and the grocery list in the wizard
  # so everything to buy is known before shopping lists are made. Restock
  # check-ins are live (not per planned week), so this reflects right now.
  class RestockSection < Section
    KEY   = "restock".freeze
    LABEL = "Restock checklist".freeze
    ICON  = "restock".freeze

    def items
      @items ||= household.restock_items.to_a
    end

    def categories
      household.restock_categories.ordered.includes(:restock_items)
    end

    def to_buy_count   = items.count(&:restock?)
    def unchecked_count = items.reject(&:checked_this_week?).size

    # The staples are always there; what counts as "planned" for the week is
    # having gone through them.
    def empty?
      items.none?(&:checked_this_week?)
    end

    def summary_line
      "#{to_buy_count} item#{'s' unless to_buy_count == 1} to restock"
    end

    def detail_line
      unchecked_count.positive? ? "#{unchecked_count} not checked yet this week" : nil
    end

    def empty_headline = "Restock checklist"
    def empty_body
      if items.empty?
        "Add the staples you keep on hand, then check them off each week."
      else
        "#{items.size} item#{'s' unless items.size == 1} to check before you shop."
      end
    end
    def cta_label      = "Check supplies"

    def page_path = restock_items_path
  end
end
