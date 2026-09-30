require "test_helper"

class WeekPrintsTest < ActionDispatch::IntegrationTest
  MONDAY = Date.new(2026, 1, 5)

  setup do
    @household = households(:one)
    sign_in users(:one)

    recipe = Recipe.create!(title: "Chicken Teriyaki Bowls 🍚", servings: 4, user: users(:one))
    recipe.recipe_ingredients.create!(ingredient: Ingredient.create!(household: households(:one), ingredient: "Rice", family: "grain"), quantity: 1.5, unit: "cup")
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

  test "the first page has no title block repeating the running header" do
    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)

    # Only the running header (once per page) names the brand and week now.
    pages = lines.count { |line| line.start_with?("Page ") }
    assert_operator pages, :>=, 1
    assert_equal pages, lines.count { |line| line.include?("Week of Jan 5") }, lines.inspect
    refute_includes lines, "Homemakers"
    assert_includes lines, "Chore chart"
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

  test "the printed chore chart puts the assignee after the title and lists the chore's tasks" do
    chore = chores(:one) # "Take out trash", assigned to Bob
    chore.chore_tasks.create!(name: "Rinse bins")
    chore.chore_tasks.create!(name: "Wheel to curb")

    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)

    assert_includes lines, "Take out trash - #{household_members(:one).name}"
    assert(lines.any? { |line| line.include?("Rinse bins") && line.include?("Wheel to curb") }, "tasks listed: #{lines.inspect}")
    refute_includes lines, "Take out trash" # the title no longer sits alone with the name below it
  end

  test "a long chore chart and to-do list each shrink onto one page" do
    80.times do |i|
      chore = @household.chores.create!(name: "Chore number #{i} with a fairly long name", frequency: "monthly")
      3.times { |t| chore.chore_tasks.create!(name: "Task #{t} for chore #{i}") }
      @household.weekly_chores.create!(chore: chore, week_start: MONDAY, scheduled_date: MONDAY + (i % 7))
      @household.todos.create!(title: "To-do number #{i}", priority: :medium, status: "in_progress", user: users(:one))
    end

    %w[chores todos].each do |section|
      pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: [ section ]).render
      assert_equal 1, page_count(pdf), "#{section} fits on one page"
      assert_match(/ cm\b/, pdf, "#{section} is drawn scaled")
      lines = pdf_text_lines(pdf)
      assert(lines.any? { |line| line.include?("number 79") }, "#{section} still includes the last item")
    end

    # Each chosen section still gets its own page.
    assert_equal 2, page_count(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores todos]).render)
  end

  test "a long chore chart and to-do list switch to two columns; short ones stay in one" do
    short = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)
    assert(short.select { |_, text| text.start_with?("Take out trash") }.all? { |x, _| x < 306 }, "short chart is one column")

    40.times do |i|
      chore = @household.chores.create!(name: "Chore number #{i}", frequency: "monthly")
      @household.weekly_chores.create!(chore: chore, week_start: MONDAY, scheduled_date: MONDAY + (i % 7))
      @household.todos.create!(title: "To-do number #{i}", priority: :medium, status: "in_progress", user: users(:one))
    end

    { "chores" => "Chore number", "todos" => "To-do number" }.each do |section, prefix|
      items = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: [ section ]).render)
                .select { |_, text| text.start_with?(prefix) }
      assert(items.any? { |x, _| x > 306 }, "#{section} uses a second column")
      assert(items.any? { |x, _| x < 306 }, "#{section} still uses the first column")
    end
  end

  test "a section that already fits prints at full size" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[todos]).render

    assert_equal 1, page_count(pdf)
    assert_no_match(/^[\d.]+ 0(\.0+)? 0(\.0+)? [\d.]+ 0(\.0+)? 0(\.0+)? cm$/, pdf, "no scaling applied")
  end

  test "recipes still run across as many pages as they need" do
    assert_not_includes WeekPlanPdf::FIT_TO_PAGE, "recipes"
  end

  private

  # Prawn writes each run of text as a hex string (<...> Tj, or [<...> kern
  # <...>] TJ when kerned); decode them back into lines.
  def pdf_text_lines(pdf)
    pdf.b.scan(/(<[0-9a-fA-F]*>)\s*Tj|\[((?:<[0-9a-fA-F]*>|[\s\d.-])*)\]\s*TJ/).map do |single, array|
      (single || array).scan(/<([0-9a-fA-F]*)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
                       .encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace)
    end
  end

  # [x, text] for each text run, x in the page's own points (a shrunk
  # section's positions are scaled back from its " cm" transform, so they're
  # comparable with the 612pt page width).
  def pdf_text_positions(pdf)
    # Prawn's scale is a translate ("1 0 0 1 tx ty cm") then the scale
    # itself ("f 0 0 f 0 0 cm"): page x = tx + f * x.
    shift, factor = pdf.b.match(/^1(?:\.0+)? 0(?:\.0+)? 0(?:\.0+)? 1(?:\.0+)? ([-\d.]+) [-\d.]+ cm\s+([\d.]+) 0(?:\.0+)? 0(?:\.0+)? [\d.]+ 0(?:\.0+)? 0(?:\.0+)? cm$/)&.captures&.map(&:to_f)
    shift, factor = 0.0, 1.0 unless factor
    pdf.b.scan(/BT\b(.*?)\bET/m).filter_map do |(block)|
      x = block[/([-\d.]+) [-\d.]+ Td/, 1]
      next unless x
      [ shift + x.to_f * factor, pdf_text_lines(block).join ]
    end
  end
end
