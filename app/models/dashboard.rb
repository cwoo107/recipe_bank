module Dashboard
  # Single source of truth for which planning areas exist, and in what
  # order — drives both the dashboard cards and the "Plan Your Week" wizard
  # steps. Adding a new planning area is one Section subclass plus one entry
  # here, not a change to the dashboard or wizard's layout code.
  def self.sections
    [
      Dashboard::MealsSection,
      Dashboard::GroceriesSection,
      Dashboard::ChoresSection,
      Dashboard::TodosSection,
      Dashboard::CalendarSection
    ]
  end

  def self.section_class(key)
    sections.find { |klass| klass::KEY == key.to_s }
  end

  def self.section_keys
    sections.map { |klass| klass::KEY }
  end
end
