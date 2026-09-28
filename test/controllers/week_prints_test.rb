require "test_helper"

class WeekPrintsTest < ActionDispatch::IntegrationTest
  MONDAY = Date.new(2026, 1, 5)

  setup do
    @household = households(:one)
    sign_in users(:one)

    recipe = Recipe.create!(title: "Chicken Teriyaki Bowls 🍚", servings: 4, user: users(:one))
    recipe.recipe_ingredients.create!(ingredient: Ingredient.create!(ingredient: "Rice", family: "grain"), quantity: 1.5, unit: "cup")
    recipe.steps.create!(content: "Steam the rice")
    @household.meals.create!(recipe:, user: users(:one), meal_name: "Dinner", date: MONDAY, servings: 4,
                             eater_ids: [ household_members(:one).id ])
    @household.meals.create!(recipe:, user: users(:one), meal_name: "Snack", date: MONDAY, servings: 2)
    @household.grocery_lists.create!(ingredient: ingredients(:one), user: users(:one), week_of: MONDAY, units: 2)
    restock_items(:one).mark_restock!
    @household.todos.create!(title: "Fix the fence", priority: :high, status: "todo", user: users(:one))
    @household.weekly_chores.create!(chore: chores(:one), week_start: MONDAY, scheduled_date: MONDAY + 1)
  end

  test "the print page lets you pick a week and pages, all ticked by default" do
    get new_week_print_url(week: "2026-01-07")

    assert_response :success
    assert_select "input[name=week][value='2026-01-05']"
    assert_select "input[type=checkbox][name='sections[]'][checked]", count: WeekPlanPdf::SECTIONS.size
    assert_select "a[href='#{new_week_print_path(week: MONDAY + 7, sections: WeekPlanPdf::SECTIONS.keys)}']", text: /Next/
    assert_select "form[action='#{week_print_path(format: :pdf)}'][target=_blank]"
  end

  test "it streams a PDF of every chosen page, without saving anything" do
    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: WeekPlanPdf::SECTIONS.keys)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match(/inline; filename="week-plan-2026-01-05.pdf"/, response.headers["Content-Disposition"])
    assert response.body.start_with?("%PDF")
    assert_operator response.body.bytesize, :>, 2_000
  end

  test "only the chosen pages go in" do
    all_pages = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: WeekPlanPdf::SECTIONS.keys).render
    one_page  = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[groceries]).render

    assert_operator page_count(all_pages), :>, page_count(one_page)
    assert_equal 1, page_count(one_page)
  end

  test "text the built-in PDF fonts can't draw (emoji) is dropped rather than failing" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[meals recipes])
    assert pdf.render.start_with?("%PDF")
  end

  test "empty weeks still print, with a note on each page" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY + 70, sections: WeekPlanPdf::SECTIONS.keys - %w[restock todos])
    assert pdf.render.start_with?("%PDF")
  end

  test "choosing no pages sends you back to pick some" do
    get week_print_url(format: :pdf, week: MONDAY.iso8601)
    assert_redirected_to new_week_print_url(week: MONDAY)
  end

  test "limited members can print too" do
    sign_in users(:two)
    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: %w[meals chores])
    assert_response :success
  end

  test "the dashboard and the last planning step link to printing" do
    get dashboard_url
    assert_select "a[href='#{new_week_print_path(week: Date.current.beginning_of_week)}']", text: /Print this week's plan/

    get plan_week_step_url(section: Dashboard.section_keys.last, week: Date.current.beginning_of_week)
    assert_select "a[href='#{new_week_print_path(week: Date.current.beginning_of_week)}']", text: /Print this week's plan/

    get plan_week_step_url(section: Dashboard.section_keys.first, week: Date.current.beginning_of_week)
    assert_select "a", text: /Print this week's plan/, count: 0
  end

  private

  def page_count(pdf) = pdf.scan(%r{/Type /Page\b}).size

  test "the to-dos page is only what's in progress" do
    in_progress = @household.todos.create!(title: "Paint the shed", priority: :medium, status: "in_progress", user: users(:one))
    @household.todos.create!(title: "Finished", priority: :low, status: "done", user: users(:one))

    printed = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[todos]).printed_todos
    assert_equal [ in_progress ], printed.to_a
  end

  test "it's set in the app's fonts, embedded in the file" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[meals]).render
    assert_match "InstrumentSerif", pdf
    assert_match "Inter", pdf
    assert_no_match(/Helvetica|Times-Roman/, pdf)
  end

  test "calendar events print in their calendar's colors" do
    source = @household.calendar_sources.create!(name: "Family", provider: "google", color: "seafoam", ical_url: "https://calendar.example.com/feed.ics", user: users(:one))
    @household.calendar_events.create!(calendar_source: source, user: users(:one), title: "Soccer practice",
                                       starts_at: MONDAY.to_time.change(hour: 17), ends_at: MONDAY.to_time.change(hour: 18))

    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[calendar]).render
    seafoam = Palette::PRINT.fetch("seafoam")
    assert_match rgb_operator(seafoam[:bg]), pdf, "card tint"
    assert_match rgb_operator(seafoam[:dot]), pdf, "legend dot"
  end

  # How Prawn writes a fill colour into the page stream: "0.46275 0.63922 0.60784 scn".
  def rgb_operator(hex)
    r, g, b = hex.scan(/../).map { |c| Regexp.escape(format("%.5f", c.to_i(16) / 255.0)[0, 6]) }
    /#{r}\d* #{g}\d* #{b}\d* scn/
  end
end
