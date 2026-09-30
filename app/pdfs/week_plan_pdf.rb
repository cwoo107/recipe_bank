require "prawn"

# A printable PDF of one week's plan — the screens the person picked (meal
# plan, recipes, grocery list, …), built in memory and streamed straight to
# the browser. Nothing is written to disk or stored.
#
#   WeekPlanPdf.new(household:, week_start:, sections: %w[meals groceries]).render
#
# Set in the app's own typefaces — Instrument Serif for headings, Inter for
# text — embedded from vendor/fonts (Prawn subsets them, so only the letters
# used end up in the file). Neither font has emoji, so #clean drops those
# rather than printing empty boxes.
class WeekPlanPdf
  SECTIONS = {
    "meals"     => { label: "Meal plan",          hint: "Breakfast, lunch and dinner for each day, plus snacks and desserts" },
    "recipes"   => { label: "Recipes",            hint: "Ingredients and steps for every recipe on this week's meal plan" },
    "groceries" => { label: "Grocery list",       hint: "The week's grocery list with check-off boxes" },
    "restock"   => { label: "Restock list",       hint: "Everything marked Restock, by store" },
    "chores"    => { label: "Chore chart",        hint: "Each day's chores and who's doing them" },
    "todos"     => { label: "To-dos",             hint: "What's in progress" },
    "calendar"  => { label: "Calendar",           hint: "The week's events, day by day" }
  }.freeze

  SAGE       = "5f734c".freeze
  SAGE_DARK  = "3f4d34".freeze
  SAGE_LIGHT = "e8ede3".freeze
  INK        = "2f3027".freeze
  MUTED      = "6f705f".freeze
  RULE       = "d4ddc9".freeze

  FONT_DIR = Rails.root.join("vendor/fonts")
  SERIF    = "Instrument Serif".freeze
  SANS     = "Inter".freeze

  # The meal planner's card colors (MealsHelper#meal_color_classes): the
  # palette's 300 shade behind, 800 for the title, 700 for the details —
  # converted from the app's oklch values, since PDFs need RGB.
  MEAL_COLORS = {
    "breakfast" => { bg: "a9cdc6", title: "354d4b", detail: "486b67" }, # seafoam
    "lunch"     => { bg: "e4d8ab", title: "63532c", detail: "937e45" }, # honey
    "dinner"    => { bg: "d0d6d8", title: "22292b", detail: "394447" }, # mist
    "snack"     => { bg: "d7d0d7", title: "2a212c", detail: "463947" }, # mauve
    "dessert"   => { bg: "d6b4b5", title: "4d3236", detail: "6e4a4f" }  # dusty rose
  }.freeze


  # These print on exactly one page each, shrunk to fit when they run long
  # (see #fit_to_page). Recipes are left to run across as many pages as
  # they need — shrinking a week of recipes onto one page would be unreadable.
  FIT_TO_PAGE = SECTIONS.keys - %w[recipes]

  # Single-column lists that switch to two columns once they'd run past one
  # page, so a long week fills the page rather than shrinking into a thin
  # strip of tiny text down the left side.
  TWO_COLUMNS_WHEN_LONG = %w[chores todos].freeze

  MARGIN = [ 64, 48, 56, 48 ].freeze

  include Prawn::View

  # page_size and list_columns are only overridden for the tall scratch
  # document #fit_to_page measures a section in.
  def initialize(household:, week_start:, sections:, page_size: "LETTER", list_columns: 1)
    @household    = household
    @week_start   = week_start
    @week         = week_start...(week_start + 7)
    @sections     = SECTIONS.keys & Array(sections)
    @page_size    = page_size
    @list_columns = list_columns
  end

  def document
    @document ||= Prawn::Document.new(
      page_size: @page_size,
      margin: MARGIN,
      info: { Title: "#{week_title} — #{@household.family_name}", Creator: "HomemakersHaven" }
    )
  end

  def render
    register_fonts
    font SANS
    fill_color INK

    # No title block on page one: the brand, household and week already run
    # along the top of every page (page_furniture).
    @sections.each_with_index do |key, index|
      start_new_page if index.positive?
      FIT_TO_PAGE.include?(key) ? fit_to_page(key) : send("#{key}_section")
    end

    page_furniture
    document.render
  end

  def filename
    "week-plan-#{@week_start.iso8601}.pdf"
  end

  # The to-dos page lists only what's in progress — not the backlog, and not
  # what's already done.
  def printed_todos
    @household.todos.includes(:assignee).where(status: "in_progress").order(:start_date, :position)
  end

  private

  def register_fonts
    font_families.update(
      SANS => {
        normal: FONT_DIR.join("Inter-Regular.ttf").to_s,
        italic: FONT_DIR.join("Inter-Italic.ttf").to_s,
        bold:   FONT_DIR.join("Inter-SemiBold.ttf").to_s
      },
      SERIF => {
        normal: FONT_DIR.join("InstrumentSerif-Regular.ttf").to_s,
        italic: FONT_DIR.join("InstrumentSerif-Italic.ttf").to_s,
        bold:   FONT_DIR.join("InstrumentSerif-Regular.ttf").to_s # the family has no bold
      }
    )
  end

  # ── Page layout ──────────────────────────────────────────────────────

  def week_title
    week_end = @week_start + 6
    ending = @week_start.month == week_end.month ? week_end.strftime("%-d, %Y") : week_end.strftime("%b %-d, %Y")
    "Week of #{@week_start.strftime('%b %-d')} – #{ending}"
  end

  # A section that must stay on one page. It's laid out once in a scratch
  # document with a very tall page to find its natural height; if that's
  # more than the page holds, it's drawn scaled down to fit. The scaled
  # drawing area is proportionally wider as well as taller, so text re-wraps
  # into the extra width rather than just shrinking — which only makes the
  # section shorter, so it's guaranteed to fit. The chore chart and to-dos
  # first try two columns (TWO_COLUMNS_WHEN_LONG) and only shrink if even
  # that won't fit.
  def fit_to_page(key)
    available = cursor
    @list_columns = 1
    needed = natural_height(key)
    if needed > available && TWO_COLUMNS_WHEN_LONG.include?(key)
      @list_columns = 2
      needed = natural_height(key)
    end
    return send("#{key}_section") if needed <= available

    factor = available / needed
    scale(factor, origin: [ 0, cursor ]) do
      # Twice the height needed, so a "does the next row fit?" check near
      # the end never trips a page break inside the box; the unused half
      # hangs off the bottom of the page, empty.
      bounding_box([ 0, cursor ], width: bounds.width / factor, height: needed * 2) do
        send("#{key}_section")
      end
    end
  end

  MEASURE_PAGE_HEIGHT = 50_000

  def natural_height(key)
    width   = document.bounds.width + MARGIN[1] + MARGIN[3]
    scratch = self.class.new(household: @household, week_start: @week_start, sections: [ key ],
                             page_size: [ width, MEASURE_PAGE_HEIGHT ], list_columns: @list_columns)
    scratch.send(:measure_section, key)
  end

  # (Run on the scratch document.) How far down the section reached,
  # counting any whole pages it filled first.
  def measure_section(key)
    register_fonts
    font SANS
    send("#{key}_section")
    (page_count - 1) * bounds.height + (bounds.top - cursor)
  end

  # Brand + week on every page, page numbers at the bottom.
  def page_furniture
    repeat(:all) do
      canvas do
        fill_color MUTED
        text_box clean("HomemakersHaven  ·  #{@household.family_name}  ·  #{week_title}"),
                 at: [ 48, bounds.top - 28 ], width: bounds.width - 96, size: 8
      end
    end
    number_pages "Page <page> of <total>", at: [ bounds.right - 120, -24 ], width: 120, align: :right, size: 8, color: MUTED
    fill_color INK
  end

  def section_heading(label, subtitle = nil)
    ensure_room(80)
    font(SERIF) { text clean(label), size: 22, color: SAGE_DARK }
    text(clean(subtitle), size: 9, color: MUTED) if subtitle
    move_down 10
  end

  def subheading(label)
    ensure_room(48)
    move_down 6
    text clean(label), size: 11, style: :bold, color: INK
    stroke_color RULE
    stroke_horizontal_rule
    move_down 6
  end

  def empty_note(message)
    text clean(message), size: 10, color: MUTED, style: :italic
    move_down 8
  end

  def ensure_room(points)
    start_new_page if cursor < points
  end

  # Tick-box items laid out in columns (left to right, then down), so long
  # lists fit on fewer pages. Items are [label, detail, checked,
  # person (optional)].
  #
  # padded: true gives every item the inset of a person's colored card
  # (#draw_checkbox), assigned or not — for lists that mix the two (chores,
  # to-dos), so an unassigned item's checkbox and text line up with the
  # assigned ones around it instead of sitting PERSON_PAD further left.
  def checkbox_columns(items, columns: 2, gap: 18, padded: false)
    width = (bounds.width - gap * (columns - 1)) / columns
    items.each_slice(columns) do |row|
      height = row.map { |label, detail, _, person| checkbox_height(label, detail, width, person, padded:) }.max
      ensure_room(height)
      top = cursor
      row.each_with_index do |(label, detail, checked, person), i|
        draw_checkbox((width + gap) * i, top, width, height, label, detail, checked, person, padded:)
      end
      move_cursor_to top - height # each item's box moves the cursor itself
    end
  end

  # A person's items sit on a card in their color, so they need padding.
  PERSON_PAD = 6

  def checkbox_height(label, detail, width, person = nil, padded: false)
    padded ||= person.present?
    inset = padded ? 16 + PERSON_PAD * 2 : 16
    # A detail line can wrap (a chore's task list), so it's measured too —
    # never less than the one-line allowance it always had.
    detail_height = detail.present? ? [ height_of(clean(detail), width: width - inset, size: 8) + 2, 11 ].max : 0
    height = [ height_of(clean(label), width: width - inset, size: 10), 9 ].max + detail_height + 5
    padded ? height + PERSON_PAD + 2 : height
  end

  def draw_checkbox(x, top, width, row_height, label, detail, checked, person = nil, padded: false)
    colors = person && Palette.print_colors(person.color)
    if colors
      fill_color colors[:card] # a person's card tint — deeper than a calendar event's bg
      fill_rounded_rectangle [ x, top ], width, row_height - 3, 4
    end

    # The card's inset — also used, without the card, for an unassigned item
    # in a padded list.
    if colors || padded
      x += PERSON_PAD
      width -= PERSON_PAD * 2
      top -= PERSON_PAD - 1
    end

    box = 9
    stroke_color MUTED
    stroke_rectangle [ x, top - 1 ], box, box
    if checked
      fill_color SAGE
      fill_rectangle [ x + 1.5, top - 2.5 ], box - 3, box - 3
    end
    fill_color INK

    # Placed text boxes rather than flowing text in a bounding box: flowing
    # text in an unsized box measures against the page's bottom margin, so on
    # a section drawn shrunk-to-fit (#fit_to_page) it would think it had run
    # off the page and start a new one. The row height was already measured
    # (#checkbox_height), so nothing needs to flow.
    text_width   = width - 16
    label        = clean(label)
    label_height = height_of(label, width: text_width, size: 10)
    colored_text_box label, at: [ x + 16, top ], width: text_width, size: 10,
                     color: checked ? MUTED : (colors ? colors[:text] : INK)
    if detail.present?
      colored_text_box clean(detail), at: [ x + 16, top - label_height ], width: text_width, size: 8,
                       color: colors ? colors[:text] : MUTED
    end
  end

  # Who's who, for pages colored by person.
  def people_legend(people)
    people = people.compact.uniq.sort_by(&:name)
    return if people.empty?

    x = 0
    top = cursor
    people.each do |person|
      name = clean(person.name)
      width = width_of(name, size: 8) + 22
      if x + width > bounds.width
        x = 0
        top -= 14
      end
      fill_color Palette.print_colors(person.color)[:dot]
      fill_circle [ x + 4, top - 5 ], 3.5
      colored_text_box name, at: [ x + 11, top ], width: width, size: 8, color: MUTED
      x += width + 6
    end
    move_cursor_to top - 18
  end

  # Minimal table: fixed column widths, wrapping cells, header repeated on
  # each new page.
  def grid(widths, header, rows, size: 9)
    draw_row(header, widths, size: 8, bold: true, fill: SAGE_LIGHT)
    rows.each do |row|
      if cursor < row_height(row, widths, size)
        start_new_page
        draw_row(header, widths, size: 8, bold: true, fill: SAGE_LIGHT)
      end
      draw_row(row, widths, size:)
    end
  end

  def draw_row(cells, widths, size:, bold: false, fill: nil)
    height = row_height(cells, widths, size, bold:)
    top = cursor
    x = 0

    cells.each_with_index do |cell, i|
      width = widths[i]
      if fill
        fill_color fill
        fill_rectangle [ x, top ], width, height
      end
      stroke_color RULE
      stroke_rectangle [ x, top ], width, height
      fill_color INK
      font(SANS, style: bold ? :bold : :normal) do
        text_box clean(cell), at: [ x + 5, top - 5 ], width: width - 10, height: height - 8, size:, leading: 1.5
      end
      x += width
    end

    move_down height
  end

  # (Prawn's `font` with a block returns the font, not the block's value.)
  def row_height(cells, widths, size, bold: false)
    tallest = 0
    font(SANS, style: bold ? :bold : :normal) do
      tallest = cells.each_with_index.map { |cell, i| height_of(clean(cell), width: widths[i] - 10, size:, leading: 1.5) }.max
    end
    tallest + 12
  end

  # Prawn's text_box has no :color option — it draws in the current fill.
  def colored_text_box(string, color:, **options)
    fill_color color
    text_box string, **options
    fill_color INK
  end

  # Emoji (and their joiners/variation selectors) aren't in either font.
  def clean(value)
    value.to_s.gsub(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/, "").squeeze(" ").strip
  end

  # ── Sections ─────────────────────────────────────────────────────────

  def week_meals
    @week_meals ||= @household.meals.where(date: @week)
                              .includes(:eaters, recipe: { recipe_ingredients: :ingredient })
                              .sort_by { |m| [ m.date, Meal::ALL_TYPES.index(m.meal_name.downcase) || 9, m.id ] }
  end

  # ── Meal plan: the planner's colored cards, one row per day ──

  CARD_GAP = 4

  def meals_section
    section_heading "Meal plan"

    calendar, extras = week_meals.partition(&:calendar_meal?)
    day_width  = 70
    meal_width = (bounds.width - day_width) / 3
    types = %w[breakfast lunch dinner]

    meal_header_row(day_width, meal_width, types)
    @week.each do |date|
      cells = types.map { |type| calendar.select { |m| m.date == date && m.meal_name.downcase == type } }
      height = [ cells.map { |meals| stack_height(meals, meal_width - 8) }.max, 26 ].max + 8

      if cursor < height
        start_new_page
        meal_header_row(day_width, meal_width, types)
      end

      top = cursor
      stroke_color RULE
      stroke_rectangle [ 0, top ], day_width, height
      colored_text_box date.strftime("%a"), at: [ 6, top - 6 ], width: day_width - 12, size: 10, style: :bold, color: INK
      colored_text_box date.strftime("%b %-d"), at: [ 6, top - 19 ], width: day_width - 12, size: 8, color: MUTED

      cells.each_with_index do |meals, i|
        x = day_width + meal_width * i
        stroke_rectangle [ x, top ], meal_width, height
        draw_card_stack(meals, x + 4, top - 4, meal_width - 8)
      end
      move_cursor_to top - height
    end

    %w[snack dessert].each do |type|
      items = extras.select { |m| m.meal_name.downcase == type }
      next if items.empty?

      subheading type.capitalize.pluralize
      checkbox_free_cards(items)
    end
  end

  def meal_header_row(day_width, meal_width, types)
    top = cursor
    fill_color SAGE_LIGHT
    fill_rectangle [ 0, top ], day_width, 20
    types.each_with_index do |type, i|
      x = day_width + meal_width * i
      fill_color MEAL_COLORS[type][:bg]
      fill_rectangle [ x, top ], meal_width, 20
      colored_text_box type.capitalize, at: [ x + 6, top - 5 ], width: meal_width - 12, size: 9, style: :bold,
               color: MEAL_COLORS[type][:title]
    end
    stroke_color RULE
    stroke_rectangle [ 0, top ], day_width + meal_width * types.size, 20
    fill_color INK
    move_cursor_to top - 20
  end

  def card_lines(meal)
    title  = clean("#{meal.recipe.title} (#{meal.servings})")
    detail = meal.eaters.any? ? clean("for #{meal.eaters.map(&:name).to_sentence}") : nil
    [ title, detail ]
  end

  def card_height(meal, width)
    title, detail = card_lines(meal)
    height = height_of(title, width: width - 12, size: 9, style: :bold)
    height += height_of(detail, width: width - 12, size: 7.5) + 1 if detail
    height + 10
  end

  def stack_height(meals, width)
    return 0 if meals.empty?

    meals.sum { |meal| card_height(meal, width) } + CARD_GAP * (meals.size - 1)
  end

  # Rounded, tinted cards like the planner's, stacked in a cell.
  def draw_card_stack(meals, x, top, width)
    meals.each do |meal|
      colors = MEAL_COLORS.fetch(meal.meal_name.downcase, MEAL_COLORS["lunch"])
      title, detail = card_lines(meal)
      height = card_height(meal, width)

      fill_color colors[:bg]
      fill_rounded_rectangle [ x, top ], width, height, 4
      colored_text_box title, at: [ x + 6, top - 5 ], width: width - 12, size: 9, style: :bold, color: colors[:title]
      if detail
        title_height = height_of(title, width: width - 12, size: 9, style: :bold)
        colored_text_box detail, at: [ x + 6, top - 6 - title_height ], width: width - 12, size: 7.5, color: colors[:detail]
      end
      top -= height + CARD_GAP
    end
    fill_color INK
  end

  # Snacks and desserts: the same cards, laid out three across.
  def checkbox_free_cards(meals, columns: 3, gap: 8)
    width = (bounds.width - gap * (columns - 1)) / columns
    meals.each_slice(columns) do |row|
      height = row.map { |meal| card_height(meal, width) }.max
      ensure_room(height + gap)
      top = cursor
      row.each_with_index { |meal, i| draw_card_stack([ meal ], (width + gap) * i, top, width) }
      move_cursor_to top - height - gap
    end
  end

  def recipes_section
    section_heading "Recipes", "Everything on this week's meal plan."

    by_recipe = week_meals.group_by(&:recipe)
    return empty_note("No meals planned this week.") if by_recipe.empty?

    by_recipe.each_with_index do |(recipe, meals), index|
      start_new_page if index.positive? && cursor < 260
      move_down 14 if index.positive?

      font(SERIF) { text clean(recipe.title), size: 18, color: INK }
      when_served = meals.map { |m| "#{m.date.strftime('%a')} #{m.meal_name.downcase}" }.uniq.to_sentence
      text clean([ ("Serves #{recipe.servings}" if recipe.servings), "On the plan: #{when_served}" ].compact.join("  ·  ")), size: 9, color: MUTED
      move_down 8

      recipe.sections.each do |section|
        ingredients = section.own_ingredients
        next if ingredients.empty?

        text(clean(section.root? ? "Ingredients" : "For the #{section.recipe.title}"), size: 10, style: :bold)
        ingredients.each do |line|
          amount = line.quantity.positive? ? helpers.display_quantity_with_unit(line.quantity.round(2), line.unit) : nil
          text clean("•  #{[ amount.presence, line.ingredient&.ingredient ].compact.join(' ')}"), size: 10
        end
        move_down 6
      end

      items = recipe.instruction_items
      next if items.empty?

      text "Steps", size: 10, style: :bold
      items.each_with_index do |item, n|
        if item.is_a?(Step)
          text clean("#{n + 1}.  #{item.content.to_plain_text.squish}"), size: 10, leading: 1.5
        else
          text clean("#{n + 1}.  Make the #{item.component_recipe.title}:"), size: 10
          item.component_recipe.steps.each_with_index do |step, s|
            indent(18) { text clean("#{(97 + s).chr}.  #{step.content.to_plain_text.squish}"), size: 10, leading: 1.5 }
          end
        end
        move_down 3
      end
    end
  end

  def groceries_section
    section_heading "Grocery list"

    items = @household.grocery_lists.where(week_of: @week).includes(:ingredient).joins(:ingredient)
                      .order("ingredients.family ASC, ingredients.ingredient ASC")
    return empty_note("No grocery list has been made for this week yet.") if items.empty?

    items.group_by { |item| item.ingredient.family.presence || "Other" }.each do |family, family_items|
      subheading family.to_s.titleize
      checkbox_columns(family_items.map do |item|
        price = item.ingredient.unit_price.present? ? format("$%.2f", item.ingredient.unit_price * item.units.to_i) : nil
        [ item.ingredient.ingredient, [ "#{item.units.to_i} #{'unit'.pluralize(item.units.to_i)}", price ].compact.join("  ·  "), item.checked? ]
      end)
    end

    subtotal = items.sum { |item| item.ingredient.unit_price.to_f * item.units.to_i }
    move_down 8
    text format("Estimated total: $%.2f", subtotal), size: 11, style: :bold, align: :right
  end

  def restock_section
    section_heading "Restock list"

    list = RestockItem.shopping_list(@household)
    return empty_note("Nothing is marked Restock right now.") if list.empty?

    list.each do |store, categories|
      subheading store
      categories.each do |category, items|
        text clean(category.name.upcase), size: 8, color: MUTED, character_spacing: 0.5
        move_down 3
        checkbox_columns(items.map { |item| [ item.name, item.brand.presence, false ] })
        move_down 4
      end
    end
  end

  def chores_section
    section_heading "Chore chart"

    Chore.auto_schedule_recurring!(@household, week_start: @week_start)
    chores = @household.weekly_chores.for_week(@week_start).includes(:assignee, chore: :chore_tasks).group_by(&:scheduled_date)
    return empty_note("No chores on the chart this week.") if chores.values.flatten.empty?

    people_legend(chores.values.flatten.map(&:assignee))

    @week.each do |date|
      day_chores = chores[date] || []
      subheading date.strftime("%A %b %-d")
      next empty_note("Nothing scheduled.") if day_chores.empty?

      # One column normally; two once the chart would run past a page
      # (@list_columns — see #fit_to_page).
      checkbox_columns(day_chores.map { |wc| chore_item(wc) }, columns: @list_columns, padded: true)
    end

    unscheduled = chores[nil] || []
    if unscheduled.any?
      subheading "Any day"
      checkbox_columns(unscheduled.map { |wc| chore_item(wc) }, columns: @list_columns, padded: true)
    end
  end

  # "Clean bathroom - Bob" on one line, with the chore's tasks (if any)
  # underneath: "Clean toilet · Mop floors · Wipe sink". A checkbox_columns
  # item.
  def chore_item(weekly_chore)
    label = [ weekly_chore.chore.name, weekly_chore.assignee&.name ].compact.join(" - ")
    tasks = weekly_chore.chore.chore_tasks.map(&:name).join("  ·  ").presence
    [ label, tasks, weekly_chore.completed?, weekly_chore.assignee ]
  end

  def todos_section
    section_heading "To-dos"

    todos = printed_todos
    return empty_note("Nothing in progress right now.") if todos.empty?

    people_legend(todos.map(&:assignee))
    # One column normally; two once the list would run past a page
    # (@list_columns — see #fit_to_page).
    checkbox_columns(todos.map do |todo|
      dates = todo.start_date && todo.end_date ? "#{todo.start_date.strftime('%b %-d')} – #{todo.end_date.strftime('%b %-d')}" : nil
      [ todo.title, [ todo.assignee&.name, todo.priority_label, dates ].compact.join("  ·  "), false, todo.assignee ]
    end, columns: @list_columns, padded: true)
  end

  def calendar_section
    section_heading "Calendar"

    events = @household.calendar_events.visible.includes(:calendar_source)
                       .in_range(@week_start.beginning_of_day, (@week_start + 7).beginning_of_day)
                       .chronological.to_a
    return empty_note("Nothing on the calendar this week.") if events.empty?

    calendar_legend(events.map(&:calendar_source).uniq)

    @week.each do |date|
      day_events = events.select { |e| e.starts_at.to_date <= date && e.ends_at.to_date >= date }
      next if day_events.empty?

      subheading date.strftime("%A %b %-d")
      day_events.each { |event| event_card(event) }
    end
  end

  # Linked calendars' colors, lightened for print (see Palette::PRINT).
  def calendar_colors_for(source)
    Palette.print_colors(source.color)
  end

  # Which color is which calendar.
  def calendar_legend(sources)
    x = 0
    top = cursor
    sources.each do |source|
      name = clean(source.name)
      width = width_of(name, size: 8) + 22
      if x + width > bounds.width
        x = 0
        top -= 14
      end
      fill_color calendar_colors_for(source)[:dot]
      fill_circle [ x + 4, top - 5 ], 3.5
      colored_text_box name, at: [ x + 11, top ], width: width, size: 8, color: MUTED
      x += width + 6
    end
    move_cursor_to top - 18
  end

  # Time on the left; a card softly tinted in the event's calendar color on the right.
  def event_card(event)
    colors  = calendar_colors_for(event.calendar_source)
    card_x  = 84
    width   = bounds.width - card_x
    title   = clean(event.title)
    detail  = clean([ event.calendar_source.name, event.location.presence ].compact.join("  ·  "))
    height  = height_of(title, width: width - 18, size: 10, style: :bold) + height_of(detail, width: width - 18, size: 8) + 12
    ensure_room(height + 4)

    top = cursor
    colored_text_box clean(event.time_range), at: [ 0, top - 5 ], width: card_x - 8, size: 9, color: MUTED

    fill_color colors[:bg]
    fill_rounded_rectangle [ card_x, top ], width, height, 4

    title_height = height_of(title, width: width - 18, size: 10, style: :bold)
    colored_text_box title, at: [ card_x + 9, top - 5 ], width: width - 18, size: 10, style: :bold, color: colors[:text]
    colored_text_box detail, at: [ card_x + 9, top - 6 - title_height ], width: width - 18, size: 8, color: colors[:text]

    move_cursor_to top - height - 5
  end

  def helpers
    @helpers ||= Class.new { include RecipeIngredientsHelper }.new
  end
end
