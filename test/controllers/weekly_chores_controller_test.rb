require "test_helper"

class WeeklyChoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get weekly_chores_url
    assert_response :success
  end

  test "index lists due chores that aren't already on this week's list" do
    get weekly_chores_url
    assert_select "#due_chores #due_chore_#{@chore.id}"
    assert_select "#due_chore_#{@chore.id} .sm\\:hidden button", text: "Add to this week"
    assert_select "#due_chore_#{@chore.id} dialog form[action*=scheduled_date]", 7
  end

  test "create adds a chore to this week's list" do
    assert_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: @chore.id, week_start: Date.current.beginning_of_week }
    end

    assert_equal households(:one), WeeklyChore.last.household
  end

  test "create is scoped to the current household's chores" do
    other_chore = chores(:two) # household :two

    assert_no_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: other_chore.id, week_start: Date.current.beginning_of_week }
    end

    assert_response :not_found
  end

  test "create can drop a due chore directly onto a day" do
    week_start = Date.current.beginning_of_week

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 2 }

    assert_equal week_start + 2, WeeklyChore.last.scheduled_date
  end

  test "create is idempotent — a second drop of the same due chore moves it instead of erroring" do
    week_start = Date.current.beginning_of_week

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 1 }
    assert_response :redirect

    assert_no_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 3 }
    end
    assert_response :redirect

    assert_equal week_start + 3, WeeklyChore.last.scheduled_date
  end

  test "move schedules a weekly chore onto a day" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 3 }

    assert_equal week_start + 3, weekly_chore.reload.scheduled_date
  end

  test "move back to an empty scheduled_date returns the chore to unscheduled" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 3)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: "" }

    assert_nil weekly_chore.reload.scheduled_date
  end

  test "reorder updates position within a day" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")
    first = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    second = households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start + 1)

    post reorder_weekly_chores_url, params: { scheduled_date: week_start + 1, order: [ second.id, first.id ] }

    assert_equal 1, second.reload.position
    assert_equal 2, first.reload.position
  end

  test "update toggles completion and stamps the chore's last_completed_at" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    patch weekly_chore_url(weekly_chore), params: { weekly_chore: { completed: true } }

    assert weekly_chore.reload.completed?
    assert_not_nil @chore.reload.last_completed_at
  end

  test "should destroy weekly chore" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    assert_difference("WeeklyChore.count", -1) do
      delete weekly_chore_url(weekly_chore)
    end
  end

  test "destroying a still-due weekly chore puts it back in the due soon list" do
    @chore.update!(last_completed_at: nil) # never completed -> always due
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    delete weekly_chore_url(weekly_chore), as: :turbo_stream

    assert_match(/due_chore_#{@chore.id}/, response.body)
  end

  test "destroying a weekly chore that isn't due yet does not reappear in due soon" do
    @chore.update!(frequency: "quarterly", last_completed_at: Date.current) # not due again for months
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    delete weekly_chore_url(weekly_chore), as: :turbo_stream

    assert_no_match(/due_chore_#{@chore.id}/, response.body)
  end

  test "create with no explicit day fills in the first day that doesn't already have a chore" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")
    households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start) # Monday taken

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start }

    assert_equal week_start + 1, WeeklyChore.last.scheduled_date # Tuesday, the first open day
  end

  test "a user in a different household cannot modify the weekly chore" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)
    sign_in users(:three) # carol, household :two

    patch weekly_chore_url(weekly_chore), params: { weekly_chore: { completed: true } }
    assert_response :not_found
  end

  test "index shows a row for each chore category" do
    get weekly_chores_url
    assert_select "#weekly_chores_cell_desktop_#{Date.current.beginning_of_week.iso8601}_#{chore_categories(:chores_one).id}"
    assert_select "#weekly_chores_cell_desktop_#{Date.current.beginning_of_week.iso8601}_#{chore_categories(:standard_cleaning_one).id}"
  end

  test "move with scope=week changes just this week" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 3, scope: "week" }

    assert_equal week_start + 3, weekly_chore.reload.scheduled_date
    assert_equal (week_start + 1).wday, @chore.reload.default_weekday
  end

  test "move going forward updates the chore's remembered day" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 3, scope: "forward" }

    assert_equal (week_start + 3).wday, @chore.reload.default_weekday
  end

  test "adding from the phone day picker lands on the chosen day in the chore's category row" do
    week_start = Date.current.beginning_of_week
    thursday = week_start + 3

    post weekly_chores_url(chore_id: @chore.id, week_start: week_start, scheduled_date: thursday.iso8601), as: :turbo_stream

    assert_equal thursday, WeeklyChore.last.scheduled_date
    assert_match(/weekly_chores_cell_mobile_#{thursday.iso8601}_#{chore_categories(:chores_one).id}/, response.body)
  end

  test "move into another category's row re-files the chore" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 1, category_key: chore_categories(:standard_cleaning_one).id }

    assert_equal chore_categories(:standard_cleaning_one), @chore.reload.chore_category
  end

  test "move into the Uncategorized row clears the category" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 1, category_key: "none" }

    assert_nil @chore.reload.chore_category_id
  end

  test "move without a category_key leaves the category alone" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 2 }

    assert_equal chore_categories(:chores_one), @chore.reload.chore_category
  end

  test "move cannot re-file a chore under another household's category" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 1, category_key: chore_categories(:chores_two).id }

    assert_response :not_found
    assert_equal chore_categories(:chores_one), @chore.reload.chore_category
  end

  test "dropping a due chore into another category's row re-files it" do
    week_start = Date.current.beginning_of_week

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 2,
                                      category_key: chore_categories(:standard_cleaning_one).id, source: "drag" }, as: :turbo_stream

    assert_equal chore_categories(:standard_cleaning_one), @chore.reload.chore_category
  end

  test "the board renders sortable category rows and the category-change prompt" do
    get weekly_chores_url
    assert_select "[data-chore-board-target=rows] [data-category-row-id=?]", chore_categories(:chores_one).id.to_s
    assert_select "dialog[data-chore-board-target=categoryDialog]"
  end

  test "board cards no longer carry hover edit/delete buttons" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    get weekly_chores_url

    assert_select "#weekly_chore_#{weekly_chore.id}" do
      assert_select "[aria-label^=Remove]", 0
      assert_select "[aria-label^='View details']", 0
    end
  end

  test "dragging a card back to Coming up removes it and shows its Coming up card" do
    @chore.update!(last_completed_at: nil)
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    delete weekly_chore_url(weekly_chore), as: :turbo_stream

    assert_nil WeeklyChore.find_by(id: weekly_chore.id)
    assert_match(/turbo-stream action="remove" targets=".weekly-chore-#{weekly_chore.id}"/, response.body)
    assert_match(/due_chore_#{@chore.id}/, response.body)
  end

  test "removing a recurring chore just this week skips it without forgetting its day" do
    week_start = Date.current.beginning_of_week
    this_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    next_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start + 7, scheduled_date: week_start + 8)

    delete weekly_chore_url(this_week, scope: "week"), as: :turbo_stream

    assert this_week.reload.skipped?
    assert_equal (week_start + 1).wday, @chore.reload.default_weekday
    assert next_week.reload.persisted?
    assert_match(/due_chore_#{@chore.id}/, response.body) # offered back in Coming up

    # Reloading the board doesn't put it straight back.
    get weekly_chores_url
    assert_select "#weekly_chore_#{this_week.id}", 0
    assert_select "#due_chore_#{@chore.id}"
  end

  test "a chore skipped this week can be added back, just for this week" do
    week_start = Date.current.beginning_of_week
    this_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    delete weekly_chore_url(this_week, scope: "week"), as: :turbo_stream

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 4 }

    refute this_week.reload.skipped?
    assert_equal week_start + 4, this_week.scheduled_date
    assert_equal (week_start + 1).wday, @chore.reload.default_weekday
  end

  test "removing a recurring chore for all weeks stops it repeating and clears later weeks" do
    week_start = Date.current.beginning_of_week
    last_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start - 7, scheduled_date: week_start - 6, this_week_only: true)
    this_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    next_week = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start + 7, scheduled_date: week_start + 8)

    delete weekly_chore_url(this_week, scope: "all"), as: :turbo_stream

    assert_nil WeeklyChore.find_by(id: this_week.id)
    assert_nil WeeklyChore.find_by(id: next_week.id)
    assert last_week.reload.persisted?
    assert_nil @chore.reload.default_weekday
  end

  test "the board renders the remove prompt" do
    get weekly_chores_url
    assert_select "dialog[data-chore-board-target=removeDialog]" do
      assert_select "button", text: "Just this week"
      assert_select "button", text: "This and all future weeks"
    end
  end

  test "board cards are tinted by assignee with no name or frequency pill, and the page has a key" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    bob = household_members(:one)

    get weekly_chores_url

    assert_select "#weekly_chore_#{weekly_chore.id}[title=?]", "Assigned to #{bob.name}"
    assert_select "#weekly_chore_#{weekly_chore.id}.#{bob.color_classes[:card].split.first}"
    assert_select "#weekly_chore_#{weekly_chore.id}", text: /Weekly/, count: 0
    assert_select "[aria-label=?]", "Who each card color belongs to" do
      assert_select "span", text: bob.name
      assert_select "span", text: /Unassigned/
    end
  end

  test "Coming up cards keep their frequency but drop the name pill" do
    @chore.update!(last_completed_at: nil)
    get weekly_chores_url

    assert_select "#due_chore_#{@chore.id}", text: /Weekly/
    assert_select "#due_chore_#{@chore.id}[title=?]", "Assigned to #{household_members(:one).name}"
  end
end
