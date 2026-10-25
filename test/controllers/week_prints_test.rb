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

  test "the print page lets you pick a week and pages, all but the recipes ticked by default" do
    get new_week_print_url(week: "2026-01-07")

    ticked = WeekPlanPdf::SECTIONS.keys - %w[recipes]
    assert_response :success
    assert_select "input[name=week][value='2026-01-05']"
    assert_select "input[type=checkbox][name='sections[]'][checked]", count: ticked.size
    assert_select "input[type=checkbox][name='sections[]'][value=recipes]:not([checked])"
    assert_select "a[href='#{new_week_print_path(week: MONDAY + 7, sections: ticked)}']", text: /Next/
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
    one_page  = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render

    assert_operator page_count(all_pages), :>, page_count(one_page)
    assert_equal 1, page_count(one_page)
  end

  test "text the built-in PDF fonts can't draw (emoji) is dropped rather than failing" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[meals recipes])
    assert pdf.render.start_with?("%PDF")
  end

  test "empty weeks still print, with a note on each page" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY + 70, sections: WeekPlanPdf::SECTIONS.keys - %w[todos])
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

    get plan_week_step_url(section: Dashboard.planner_section_keys.last, week: Date.current.beginning_of_week)
    assert_select "a[href='#{new_week_print_path(week: Date.current.beginning_of_week)}']", text: /Print this week's plan/

    get plan_week_step_url(section: Dashboard.planner_section_keys.first, week: Date.current.beginning_of_week)
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

  test "the to-dos page is only what's planned for the week" do
    in_progress = @household.todos.create!(title: "Paint the shed", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one))
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

  test "the portrait chore chart puts the assignee after the title and lists the chore's tasks" do
    chore = chores(:one) # "Take out trash", assigned to Bob
    chore.chore_tasks.create!(name: "Rinse bins")
    chore.chore_tasks.create!(name: "Wheel to curb")

    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores], layouts: { "chores" => "portrait" }).render)

    assert_includes lines, "Take out trash - #{household_members(:one).name}"
    assert(lines.any? { |line| line.include?("Rinse bins") && line.include?("Wheel to curb") }, "tasks listed: #{lines.inspect}")
    refute_includes lines, "Take out trash" # the title no longer sits alone with the name below it
  end

  test "a long chore chart and to-do list each shrink onto one page" do
    80.times do |i|
      chore = @household.chores.create!(name: "Chore number #{i} with a fairly long name", frequency: "monthly")
      3.times { |t| chore.chore_tasks.create!(name: "Task #{t} for chore #{i}") }
      @household.weekly_chores.create!(chore: chore, week_start: MONDAY, scheduled_date: MONDAY + (i % 7))
      @household.todos.create!(title: "To-do number #{i}", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one))
    end

    %w[chores todos].each do |section|
      pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: [ section ]).render
      assert_equal 1, page_count(pdf), "#{section} fits on one page"
      assert_match(/ cm\b/, pdf, "#{section} is drawn scaled")
      lines = pdf_text_lines(pdf)
      assert(lines.any? { |line| line.include?("number 79") }, "#{section} still includes the last item")
    end

    # Picked together, they share the one page.
    assert_equal 1, page_count(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores todos]).render)
  end

  test "a long chore chart and to-do list switch to two columns; short ones stay in one" do
    short = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)
    assert(short.select { |_, text| text.start_with?("Take out trash") }.all? { |x, _| x < 306 }, "short chart is one column")

    40.times do |i|
      chore = @household.chores.create!(name: "Chore number #{i}", frequency: "monthly")
      @household.weekly_chores.create!(chore: chore, week_start: MONDAY, scheduled_date: MONDAY + (i % 7))
      @household.todos.create!(title: "To-do number #{i}", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one))
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

  test "unassigned chores and to-dos line up with the assigned ones' colored cards" do
    bob = household_members(:one)
    unassigned = @household.chores.create!(name: "Sweep porch", frequency: "monthly")
    @household.weekly_chores.create!(chore: unassigned, week_start: MONDAY, scheduled_date: MONDAY + 1, assignee: nil)
    @household.todos.create!(title: "Assigned job", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one), assignee: bob)
    @household.todos.create!(title: "Unassigned job", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one))

    { "chores" => [ "Take out trash - #{bob.name}", "Sweep porch" ],
      "todos"  => [ "Assigned job", "Unassigned job" ] }.each do |section, (assigned, unassigned_label)|
      positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: [ section ], layouts: { "chores" => "portrait" }).render)
      x_of = ->(label) { positions.find { |_, text| text == label }&.first }

      assert x_of.(assigned), "#{section}: found #{assigned.inspect} in #{positions.map(&:last).inspect}"
      assert_in_delta x_of.(assigned), x_of.(unassigned_label), 0.01, "#{section}: labels start at the same x"
    end
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

  # Each page's [width, height] in points, in order.
  def page_sizes(pdf) = pdf.scan(%r{/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]}).map { |w, h| [ w.to_f, h.to_f ] }

  LETTER_PORTRAIT  = [ 612.0, 792.0 ].freeze
  LETTER_LANDSCAPE = [ 792.0, 612.0 ].freeze

  test "the print page offers the chore chart landscape (the default) or portrait" do
    get new_week_print_url(week: MONDAY.iso8601)

    assert_select "input[type=radio][name='layouts[chores]'][value=landscape][checked]"
    assert_select "input[type=radio][name='layouts[chores]'][value=portrait]:not([checked])"
  end

  test "the chore chart prints landscape by default, between portrait pages" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[meals chores calendar]).render

    assert_equal [ LETTER_PORTRAIT, LETTER_LANDSCAPE, LETTER_PORTRAIT ], page_sizes(pdf)
  end

  test "a landscape chore chart can be the first page" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores calendar]).render

    assert_equal [ LETTER_LANDSCAPE, LETTER_PORTRAIT ], page_sizes(pdf)
  end

  test "portrait keeps the chore chart as the list by day" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores], layouts: { "chores" => "portrait" }).render

    assert_equal [ LETTER_PORTRAIT ], page_sizes(pdf)
  end

  test "the landscape chore chart is laid out like the Week View: categories down, days across" do
    chore = chores(:one) # "Take out trash", assigned to Bob, in "Chores"
    chore.chore_tasks.create!(name: "Rinse bins")

    positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)
    x_of = ->(label) { positions.find { |_, text| text == label }&.first }
    texts = positions.map(&:last)

    assert_includes texts, "Mon 5"
    assert_includes texts, "Sun 11"
    assert(texts.any? { |text| text.include?("Rinse bins") }, "tasks on the card: #{texts.inspect}")
    # The chore sits in Tuesday's column (it's scheduled Mon + 1).
    assert_operator x_of.("Take out trash"), :>, x_of.("Tue 6") - 1
    assert_operator x_of.("Take out trash"), :<, x_of.("Wed 7")
  end

  test "a landscape chore chart with lots of chores still fits on one page" do
    category = @household.chore_categories.create!(name: "Kitchen")
    15.times do |n|
      chore = @household.chores.create!(name: "Chore #{n}", frequency: "monthly", chore_category: category, assignee: household_members(:one))
      3.times { |t| chore.chore_tasks.create!(name: "Step #{t} of a fairly long task description") }
      @household.weekly_chores.create!(chore:, week_start: MONDAY, scheduled_date: MONDAY + (n % 7))
    end

    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render
    assert_equal [ LETTER_LANDSCAPE ], page_sizes(pdf)
  end

  test "the orientation picked on the print page reaches the PDF" do
    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: %w[chores], layouts: { chores: "portrait" })
    assert_equal [ LETTER_PORTRAIT ], page_sizes(response.body)

    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: %w[chores])
    assert_equal [ LETTER_LANDSCAPE ], page_sizes(response.body)
  end

  # ── Shopping list: groceries, then restock, on one page ──

  test "the print page has one Shopping list in place of the grocery and restock pages" do
    get new_week_print_url(week: MONDAY.iso8601)

    assert_select "input[name='sections[]'][value=shopping][checked]"
    assert_select "input[name='sections[]'][value=groceries]", 0
    assert_select "input[name='sections[]'][value=restock]", 0
    assert_select "input[type=radio][name='layouts[shopping]'][value=portrait][checked]"
    assert_select "input[type=radio][name='layouts[shopping]'][value=landscape]:not([checked])"
  end

  test "older links naming the grocery or restock page get the shopping list" do
    get new_week_print_url(week: MONDAY.iso8601, sections: %w[groceries])
    assert_select "input[name='sections[]'][value=shopping][checked]"

    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: %w[restock])
    assert_equal 1, page_count(response.body)
  end

  test "the shopping list is the groceries, then the restock list, on one page" do
    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render)

    groceries = lines.index("Groceries")
    restock   = lines.index("Restock")
    assert groceries, "groceries heading in #{lines.inspect}"
    assert restock, "restock heading in #{lines.inspect}"
    assert_operator groceries, :<, restock
    assert_includes lines, restock_items(:one).name
  end

  test "with nothing marked Restock, the shopping list is just the groceries" do
    restock_items(:one).mark_stocked! # the only one setup marked Restock
    assert_empty RestockItem.shopping_list(@household)

    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render)

    assert_includes lines, "Groceries"
    assert_not_includes lines, "Restock"
  end

  test "the shopping list prints portrait by default, landscape when picked" do
    portrait  = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render
    landscape = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping], layouts: { "shopping" => "landscape" }).render

    assert_equal [ LETTER_PORTRAIT ], page_sizes(portrait)
    assert_equal [ LETTER_LANDSCAPE ], page_sizes(landscape)

    get week_print_url(format: :pdf, week: MONDAY.iso8601, sections: %w[shopping], layouts: { shopping: "landscape" })
    assert_equal [ LETTER_LANDSCAPE ], page_sizes(response.body)
  end

  test "the grocery total sits on the Groceries heading's line, at the right of its column" do
    positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render)
    heading = positions.find { |_, text| text == "Groceries" }
    total   = positions.find { |_, text| text.start_with?("Estimated total") }

    assert heading && total, positions.map(&:last).inspect
    assert_operator total.first, :>, heading.first + 100 # pushed right, past the heading
    assert_operator total.first, :<, 260                 # but within the first of two columns
  end

  # Enough produce to fill the left column and run into the right one.
  def fill_produce(count)
    count.times do |n|
      ingredient = @household.ingredients.create!(ingredient: "Produce item #{n.to_s.rjust(2, '0')}", family: "produce")
      @household.grocery_lists.create!(ingredient:, user: users(:one), week_of: MONDAY, units: 1)
    end
  end

  test "the shopping list reads down the left column, then the right, repeating a split section's title" do
    fill_produce(40)
    positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render)
    x_of = ->(label) { positions.find { |_, text| text == label }&.first }

    assert_operator x_of.("Produce item 00"), :<, 100   # starts in the left column
    assert_operator x_of.("Produce item 39"), :>, 200   # ends in the right one
    produce_titles = positions.select { |_, text| text == "Produce" }
    assert_equal 2, produce_titles.size, "the split section's title shows at the top of the next column too"
    assert_operator produce_titles.map(&:first).max, :>, 200

    # The restock list picks up where the groceries end — in the right column here.
    assert_operator x_of.("Restock"), :>, 200
  end

  test "a short shopping list stays in the left column, restock right under the groceries" do
    positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render)
    x_of = ->(label) { positions.find { |_, text| text == label }&.first }

    assert_in_delta x_of.("Groceries"), x_of.("Restock"), 0.01
  end

  test "a very long shopping list still fits one page" do
    fill_produce(140)
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping]).render

    assert_equal 1, page_count(pdf)
    assert(pdf_text_lines(pdf).any? { |line| line.include?("Produce item 139") })
  end

  test "landscape spreads the shopping list over three columns" do
    fill_produce(60)
    positions = pdf_text_positions(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[shopping], layouts: { "shopping" => "landscape" }).render)

    column_starts = positions.select { |_, text| text == "Produce" }.map { |x, _| x.round }.uniq
    assert_equal 3, column_starts.size, positions.map(&:last).inspect
  end

  test "the shopping list stays on the print page unless both grocery and restock steps are left out" do
    @household.update!(excluded_planner_sections: %w[groceries])
    assert_includes @household.default_print_sections, "shopping"

    @household.update!(excluded_planner_sections: %w[groceries restock])
    assert_not_includes @household.default_print_sections, "shopping"
  end

  # ── Chore chart + to-dos on one page ──

  test "the chore chart and to-dos share a page when both are picked" do
    @household.todos.create!(title: "Paint the shed", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one))
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[meals chores todos calendar]).render

    # Meals, then chores + to-dos on one landscape page, then the calendar.
    assert_equal [ LETTER_PORTRAIT, LETTER_LANDSCAPE, LETTER_PORTRAIT ], page_sizes(pdf)

    lines = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores todos]).render)
    assert_operator lines.index("Chore chart"), :<, lines.index("To-dos")
    assert_includes lines, "Paint the shed"
  end

  test "the shared page follows the chore chart's orientation" do
    pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores todos], layouts: { "chores" => "portrait" }).render
    assert_equal [ LETTER_PORTRAIT ], page_sizes(pdf)
  end

  test "either one still prints on its own" do
    only_chores = pdf_text_lines(WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores]).render)
    only_todos  = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[todos]).render

    assert_not_includes only_chores, "To-dos"
    assert_equal [ LETTER_PORTRAIT ], page_sizes(only_todos)
  end

  test "a long chore chart and to-do list still fit on their one page" do
    20.times { |n| @household.todos.create!(title: "In-progress job #{n} with a longer title", priority: :medium, status: "in_progress", planned_week: MONDAY, user: users(:one)) }
    category = @household.chore_categories.create!(name: "Kitchen")
    12.times do |n|
      chore = @household.chores.create!(name: "Chore #{n}", frequency: "monthly", chore_category: category)
      @household.weekly_chores.create!(chore:, week_start: MONDAY, scheduled_date: MONDAY + (n % 7))
    end

    %w[landscape portrait].each do |layout|
      pdf = WeekPlanPdf.new(household: @household, week_start: MONDAY, sections: %w[chores todos], layouts: { "chores" => layout }).render
      assert_equal 1, page_count(pdf), "#{layout} fits one page"
    end
  end

  test "the print page groups the chore chart and to-dos, each with its own tick box, under one orientation" do
    get new_week_print_url(week: MONDAY.iso8601)

    assert_select "#print_options_chores_and_todos" do
      assert_select "input[type=checkbox][name='sections[]'][value=chores][checked]"
      assert_select "input[type=checkbox][name='sections[]'][value=todos][checked]"
      assert_select "[role=radiogroup][aria-label=?]", "Chore chart and to-dos orientation", 1
      assert_select "input[type=radio][name='layouts[chores]']", 2
    end
    assert_select "input[name='sections[]'][value=chores]", 1
    assert_select "input[name='sections[]'][value=todos]", 1
  end

  # ── Each page's own Print button ──

  test "each planning page has a Print button straight to its own PDF" do
    {
      meals_url(date: MONDAY.iso8601)          => [ "meals", "Print meal plan" ],
      grocery_lists_url(date: MONDAY.iso8601)  => [ "shopping", "Print shopping list" ],
      weekly_chores_url(date: MONDAY.iso8601)  => [ "chores", "Print chore chart" ],
      week_calendars_url(date: MONDAY.iso8601) => [ "calendar", "Print calendar" ]
    }.each do |page, (section, label)|
      get page
      assert_select "a[target=_blank][href=?]", week_print_path(format: :pdf, week: MONDAY.iso8601, sections: [ section ]), text: /#{label}/
    end

    get todos_url
    assert_select "a[target=_blank][href=?]", week_print_path(format: :pdf, week: Date.current.beginning_of_week.iso8601, sections: [ "todos" ]), text: /Print to-dos/
  end

  test "a limited member gets the Print buttons too" do
    sign_in users(:two) # bob, limited
    get grocery_lists_url(date: MONDAY.iso8601)
    assert_select "a", text: /Print shopping list/
  end

  test "a recipe prints on its own" do
    recipe = Recipe.find_by!(title: "Chicken Teriyaki Bowls 🍚")

    get recipe_url(recipe)
    assert_select "a[target=_blank][href=?]", recipe_print_path(recipe, format: :pdf), text: /Print recipe/

    get recipe_print_url(recipe, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    lines = pdf_text_lines(response.body)
    assert_includes lines, "Chicken Teriyaki Bowls"
    assert(lines.any? { |line| line.include?("Steam the rice") }, lines.inspect)
  end

  test "another household's private recipe can't be printed" do
    theirs = Recipe.create!(title: "Secret stew", servings: 4, user: users(:three), visibility: "private")

    get recipe_print_url(theirs, format: :pdf)
    assert_response :not_found
  end

  test "the dashboard steps between weeks like the meal planner, and its print button follows" do
    this_week = Date.current.beginning_of_week

    get dashboard_url
    assert_select "a[href=?]", dashboard_path(date: (this_week - 7).iso8601), text: /Previous Week/
    assert_select "a[href=?]", dashboard_path(date: (this_week + 7).iso8601), text: /Next Week/
    assert_select "a[href=?]", new_week_print_path(week: this_week), text: /Print this week's plan/

    later = this_week + 14
    get dashboard_url(date: (later + 3).iso8601) # any day in the week
    assert_select "h1", text: /Week of #{later.strftime('%b %-d')}/
    assert_select "a[href=?]", new_week_print_path(week: later), text: /Print plan for week of #{later.strftime('%b %-d')}/
    assert_select "a[href=?]", dashboard_path(date: (later - 7).iso8601), text: /Previous Week/
  end

  test "a week the planner can't plan doesn't offer to plan it" do
    get dashboard_url(date: (Date.current.beginning_of_week - 7).iso8601)

    assert_response :success
    assert_select "h1", text: /LastWeek/
    assert_select "a[href^='/plan-week?week=#{(Date.current.beginning_of_week - 7).iso8601}']", count: 0
    assert_select "a", text: /Plan your week|Reopen the plan/, count: 0
  end
end
