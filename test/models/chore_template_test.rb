require "test_helper"

# The Chore Chart's template library (config/chore_templates.yml) and
# copying a template onto a household's chart.
class ChoreTemplateTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
  end

  test "new households start with an empty chore chart" do
    household = Household.create!(family_name: "New Household", owner: users(:one))

    assert_empty household.chore_categories
    assert_empty household.chores
  end

  test "every template's chores are valid" do
    assert ChoreTemplate.all.any?
    ChoreTemplate.all.each do |template|
      assert template.name.present?, "#{template.key} needs a name"
      assert template.chores.any?, "#{template.key} has no chores"
      template.chores.each do |chore|
        assert_includes Chore::FREQUENCIES, chore.frequency, "#{template.key}: #{chore.name}"
        # Only weekly/biweekly chores have a remembered day (Chore::RECURRING_FREQUENCIES),
        # and each of those should land on the chart on one.
        if Chore::RECURRING_FREQUENCIES.include?(chore.frequency)
          assert_includes 0..6, chore.weekday, "#{template.key}: #{chore.name} needs a valid day"
        else
          assert_nil chore.weekday, "#{template.key}: #{chore.name} is #{chore.frequency}, so it can't have a day"
        end
      end
    end
  end

  test "find raises not found for an unknown key" do
    assert_raises(ActiveRecord::RecordNotFound) { ChoreTemplate.find("nope") }
  end

  test "adding a template copies the category and its chores, frequencies and tasks" do
    template = ChoreTemplate.find("admin")

    category = assert_difference -> { @household.chore_categories.count } => 1,
                                 -> { @household.chores.count } => template.chores.size do
      template.add_to!(@household)
    end

    assert_equal "Admin", category.name
    assert_equal @household.chore_categories.maximum(:position), category.position
    template.chores.each do |item|
      chore = category.chores.find_by!(name: item.name)
      assert_equal item.frequency, chore.frequency
      assert_equal item.tasks, chore.chore_tasks.map(&:name)
      assert_nil chore.assignee
    end
  end

  test "weekly and biweekly chores go on the chart on their day from this week" do
    template = ChoreTemplate.find("yard")
    template.add_to!(@household)
    week_start = Date.current.beginning_of_week

    mow  = @household.chores.find_by!(name: "Mow the lawn")
    weed = @household.chores.find_by!(name: "Weed garden beds")
    assert_equal 6, mow.default_weekday
    assert_equal 0, weed.default_weekday
    assert_equal week_start, weed.default_weekday_started_on

    Chore.auto_schedule_recurring!(@household, week_start: week_start)
    assert_equal [ mow.default_weekday_in(week_start) ], mow.weekly_chores.where(week_start: week_start).pluck(:scheduled_date)
    assert weed.weekly_chores.exists?(week_start: week_start)
    assert_not weed.scheduled_on_week?(week_start + 7), "biweekly skips next week"

    trim = @household.chores.find_by!(name: "Trim hedges and shrubs")
    assert_nil trim.default_weekday
    assert_includes Chore.due_soon(@household, week_start: week_start), trim
  end

  test "adding into an existing category of the same name skips chores it already has" do
    category = chore_categories(:standard_cleaning_one)
    @household.chores.create!(name: "clean bathrooms", frequency: "monthly", chore_category: category)
    template = ChoreTemplate.find("standard_cleaning")

    assert_equal template.chores.size - 1, template.missing_chores_for(@household).size
    assert_no_difference -> { @household.chore_categories.count } do
      assert_difference -> { category.chores.count } => template.chores.size - 1 do
        assert_equal category, template.add_to!(@household)
      end
    end
    assert_equal "monthly", category.chores.find_by!(name: "clean bathrooms").frequency
  end

  test "adding a template twice doesn't duplicate anything" do
    template = ChoreTemplate.find("deep_cleaning")
    template.add_to!(@household)

    assert_empty template.missing_chores_for(@household)
    assert_no_difference [ -> { @household.chores.count }, -> { ChoreTask.count } ] do
      template.add_to!(@household)
    end
  end
end
