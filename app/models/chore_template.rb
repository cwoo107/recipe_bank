# A ready-made chore category from the template library
# (config/chore_templates.yml) — "Admin", "Deep Cleaning" and so on, each
# with a set of chores. Adding one to a household works like saving a public
# recipe: the category and its chores (frequency, description and tasks) are
# copied onto the household's Chore Chart, where they're the household's own
# to edit like any other.
class ChoreTemplate
  # weekday is 0–6 (Sunday first, like Chore#default_weekday), or nil for a
  # chore with no set day.
  Item = Data.define(:name, :frequency, :description, :tasks, :weekday) do
    def frequency_label       = Chore::FREQUENCY_LABELS.fetch(frequency)
    def frequency_pill_classes = Chore::FREQUENCY_PILL_CLASSES.fetch(frequency)
    def day_name              = weekday && Date::DAYNAMES[weekday]
  end

  attr_reader :key, :name, :description, :chores

  def self.all
    @all ||= YAML.load_file(Rails.root.join("config/chore_templates.yml")).map do |key, attrs|
      new(key: key, **attrs.symbolize_keys)
    end.freeze
  end

  def self.find(key)
    all.find { |template| template.key == key.to_s } or raise ActiveRecord::RecordNotFound, "No chore template #{key.inspect}"
  end

  def initialize(key:, name:, description: nil, chores: [])
    @key = key
    @name = name
    @description = description
    @chores = chores.map do |chore|
      Item.new(name: chore["name"], frequency: chore["frequency"].to_s,
               description: chore["description"], tasks: Array(chore["tasks"]),
               weekday: chore["day"] && Date::DAYNAMES.index(chore["day"].to_s.capitalize))
    end.freeze
  end

  def to_param = key

  # The household's category with this template's name, if it has one.
  def category_in(household)
    household.chore_categories.find_by("LOWER(name) = ?", name.downcase)
  end

  # This template's chores the household doesn't have in its matching
  # category yet — all of them when it has no such category.
  def missing_chores_for(household)
    category = category_in(household)
    return chores if category.nil?

    taken = category.chores.pluck(:name).map(&:downcase).to_set
    chores.reject { |chore| taken.include?(chore.name.downcase) }
  end

  # Copies this template onto the household's chart and returns the
  # category. If the household already has a category with this name, the
  # chores go into it, skipping any it already has — so adding a template
  # twice doesn't double anything up. Weekly and biweekly chores with a day
  # are scheduled on it from this week on, as if dragged there on the board;
  # daily ones are on the board every day anyway, and the rest wait in
  # Coming up until they're due.
  def add_to!(household)
    ChoreCategory.transaction do
      missing  = missing_chores_for(household)
      category = category_in(household) || household.chore_categories.create!(name: name)

      missing.each do |item|
        chore = household.chores.create!(name: item.name, frequency: item.frequency,
                                         description: item.description, chore_category: category)
        item.tasks.each { |task| chore.chore_tasks.create!(name: task) }
        chore.reschedule_forward!(item.weekday, from_week: Date.current.beginning_of_week) if item.weekday
      end

      category
    end
  end
end
