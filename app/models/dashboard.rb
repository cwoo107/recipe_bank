module Dashboard
  # Single source of truth for which planning areas exist, and in what
  # order — drives the dashboard cards (and, with the calendar moved first,
  # the "Plan Your Week" wizard steps — planner_sections below). Adding a new planning area is one Section subclass plus one entry
  # here, not a change to the dashboard or wizard's layout code.
  def self.sections
    [
      Dashboard::MealsSection,
      Dashboard::RestockSection,
      Dashboard::GroceriesSection,
      Dashboard::ChoresSection,
      Dashboard::TodosSection,
      Dashboard::CalendarSection
    ]
  end

  # The "Plan Your Week" wizard's steps, in order: the calendar first — the
  # week's commitments in view before planning meals, shopping and chores —
  # then the rest as above. The dashboard cards keep the order above.
  def self.planner_sections
    calendar, rest = sections.partition { |klass| klass::KEY == Dashboard::CalendarSection::KEY }
    calendar + rest
  end

  def self.planner_section_keys
    planner_sections.map { |klass| klass::KEY }
  end

  def self.section_class(key)
    sections.find { |klass| klass::KEY == key.to_s }
  end

  def self.section_keys
    sections.map { |klass| klass::KEY }
  end
end
