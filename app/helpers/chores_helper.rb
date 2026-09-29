module ChoresHelper
  # [label, wday] pairs for the "Day" dropdown, in the household's week order.
  def chore_weekday_options
    start = current_household&.week_start_day || 1
    (0..6).map { |i| (start + i) % 7 }.map { |wday| [ Date::DAYNAMES[wday], wday ] }
  end

  # Board rows as [key, name, category]: one per category in order, plus
  # "Uncategorized" (category nil) for chores without one — only when there
  # are any. Keys match the cells' data-category-key and
  # chore_board_category_key below.
  def chore_board_rows(categories, chores)
    rows = categories.map { |category| [ category.id.to_s, category.name, category ] }
    rows << [ "none", "Uncategorized", nil ] if chores.any? { |chore| chore.chore_category_id.nil? }
    rows
  end

  # A Chore Chart card's background and border: the assignee's color, or
  # plain white when nobody's assigned. The page's assignee key
  # (weekly_chores/_assignee_key) says who's who.
  def chore_card_color_classes(assignee)
    assignee ? assignee.color_classes[:card] : "bg-white border-gray-200 dark:bg-[#242b1e] dark:border-white/10"
  end

  # Spoken/hover text standing in for the old name pill, so the assignment
  # isn't conveyed by color alone.
  def chore_card_assignee_label(assignee)
    assignee ? "Assigned to #{assignee.name}" : "Unassigned"
  end

  def chore_board_category_key(chore)
    chore.chore_category_id&.to_s || "none"
  end

  # "Today", "Overdue · Sep 21", or just "Oct 3".
  def chore_due_label(date)
    return "Today" if date == Date.current
    return "Overdue · #{date.strftime('%b %-d')}" if date < Date.current
    date.strftime(date.year == Date.current.year ? "%a, %b %-d" : "%b %-d, %Y")
  end

  def chore_due_label_classes(date)
    date <= Date.current ? "text-terracotta-700 dark:text-terracotta-300 font-medium" : "text-gray-700 dark:text-gray-300"
  end
end
