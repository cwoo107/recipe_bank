require "prawn"

# A printable PDF of one week's plan — the screens the person picked (meal
# plan, recipes, grocery list, …), built in memory and streamed straight to
# the browser. Nothing is written to disk or stored.
#
#   WeekPlanPdf.new(household:, week_start:, sections: %w[meals groceries]).render
#
# Fonts, colors and recipe layout come from PdfBasics. Neither font has
# emoji, so #clean drops those rather than printing empty boxes.
class WeekPlanPdf
  SECTIONS = {
    "meals"     => { label: "Meal plan",          hint: "Breakfast, lunch and dinner for each day, plus snacks and desserts" },
    "recipes"   => { label: "Recipes",            hint: "Ingredients and steps for every recipe on this week's meal plan" },
    "shopping"  => { label: "Shopping list",      hint: "The week's grocery list and restock items" },
    "chores"    => { label: "Chore chart",        hint: "Each day's chores and who's doing them" },
    "todos"     => { label: "To-dos",             hint: "What's planned this week" },
    "calendar"  => { label: "Calendar",           hint: "All events coming up this week" }
  }.freeze

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
  NOTE_MEAL_COLORS = { bg: "e3dedb", title: "3d3633", detail: "6b625d" }.freeze # taupe — not cooked


  # Sections that share a page when both are picked (each can still be
  # printed on its own): the chore chart with the to-dos underneath, in the
  # chore chart's orientation. See #pages.
  SHARED_PAGES = { "chores_and_todos" => %w[chores todos] }.freeze

  # These print on exactly one page each, shrunk to fit when they run long
  # (see #fit_to_page). Recipes are left to run across as many pages as
  # they need — shrinking a week of recipes onto one page would be unreadable.
  # The shopping list fits itself to its page, column by column
  # (#shopping_section).
  FIT_TO_PAGE = SECTIONS.keys - %w[recipes shopping] + SHARED_PAGES.keys

  # Single-column lists that switch to two columns once they'd run past one
  # page, so a long week fills the page rather than shrinking into a thin
  # strip of tiny text down the left side.
  TWO_COLUMNS_WHEN_LONG = %w[chores todos chores_and_todos].freeze

  MARGIN = [ 64, 48, 56, 48 ].freeze

  # Pages that print either way round, picked on the print page — each
  # with its own default. The chore chart in landscape is laid out like the
  # Chore Chart's Week View — a row per category, a column per day — and in
  # portrait lists each day's chores down the page. The shopping list keeps
  # its order either way and just fits more columns across in landscape.
  # Every other page stays portrait.
  DEFAULT_LAYOUTS = { "chores" => "landscape", "shopping" => "portrait" }.freeze
  ORIENTABLE      = DEFAULT_LAYOUTS.keys.freeze
  LAYOUTS         = %w[landscape portrait].freeze

  # Each orientable page's layout from the print page's layouts[...]
  # params, falling back to its default.
  def self.layouts_from(params)
    params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    DEFAULT_LAYOUTS.to_h { |key, default| [ key, LAYOUTS.include?(params[key].to_s) ? params[key].to_s : default ] }
  end

  include Prawn::View
  include PdfBasics

  # page_size and list_columns are only overridden for the tall scratch
  # document #fit_to_page measures a section in.
  def initialize(household:, week_start:, sections:, layouts: {}, page_size: "LETTER", list_columns: 1)
    @household    = household
    @week_start   = week_start
    @week         = week_start...(week_start + 7)
    @sections     = SECTIONS.keys & Array(sections)
    @layouts      = self.class.layouts_from(layouts)
    @page_size    = page_size
    @list_columns = list_columns
  end

  def document
    @document ||= Prawn::Document.new(
      page_size: @page_size,
      page_layout: page_layout_for(pages.first),
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
    pages.each_with_index do |key, index|
      start_new_page(layout: page_layout_for(key)) if index.positive?
      FIT_TO_PAGE.include?(key) ? fit_to_page(key) : send("#{key}_section")
    end

    page_furniture
    document.render
  end

  def filename
    "week-plan-#{@week_start.iso8601}.pdf"
  end

  # The to-dos page lists only what's planned for the week, in the order
  # it'll be worked through — not the backlog, and not what's already done.
  def printed_todos
    Todo.open_for_week(@household, @week_start).includes(:assignee)
  end

  private

  # ── Page layout ──────────────────────────────────────────────────────

  def landscape?(key) = @layouts[key] == "landscape"

  # The picked sections as pages, in order — two that share a page
  # (SHARED_PAGES) become that page when both are picked.
  def pages
    SHARED_PAGES.reduce(@sections) do |keys, (page, parts)|
      next keys unless (parts - keys).empty?

      keys.flat_map { |key| key == parts.first ? [ page ] : (parts.include?(key) ? [] : [ key ]) }
    end
  end

  # A custom page size is the measuring scratch document (#natural_height),
  # which is already the right width — turning it would swap its sides.
  def page_layout_for(key)
    return :portrait if @page_size.is_a?(Array)

    landscape?(key == "chores_and_todos" ? "chores" : key) ? :landscape : :portrait
  end

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
    scratch = self.class.new(household: @household, week_start: @week_start, sections: [ key ], layouts: @layouts,
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

  # Brand + week on every page, page numbers at the bottom. Drawn page by
  # page (dynamic), against each page's own size — a landscape chore chart
  # can sit between portrait pages.
  def page_furniture
    total = page_count
    repeat(:all, dynamic: true) do
      canvas do
        fill_color MUTED
        text_box clean("HomemakersHaven  ·  #{@household.family_name}  ·  #{week_title}"),
                 at: [ 48, bounds.top - 28 ], width: bounds.width - 96, size: 8
        text_box "Page #{page_number} of #{total}", at: [ bounds.right - 168, 32 ], width: 120, align: :right, size: 8
      end
    end
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
    title  = clean(meal.note_only? ? meal.title : "#{meal.title} (#{meal.servings})")
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
      colors = meal.note_only? ? NOTE_MEAL_COLORS : MEAL_COLORS.fetch(meal.meal_name.downcase, MEAL_COLORS["lunch"])
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

    by_recipe = week_meals.reject(&:note_only?).group_by(&:recipe)
    return empty_note("No meals planned this week.") if by_recipe.empty?

    by_recipe.each_with_index do |(recipe, meals), index|
      start_new_page if index.positive? && cursor < 260
      move_down 14 if index.positive?

      font(SERIF) { text clean(recipe.title), size: 18, color: INK }
      when_served = meals.map { |m| "#{m.date.strftime('%a')} #{m.meal_name.downcase}" }.uniq.to_sentence
      text clean([ ("Serves #{recipe.servings}" if recipe.servings), "On the plan: #{when_served}" ].compact.join("  ·  ")), size: 9, color: MUTED
      move_down 8

      recipe_ingredients_and_steps(recipe)
    end
  end

  # ── Shopping list: the week's groceries, then the restock list ──
  # One page, read in columns like a newspaper: the groceries by family
  # (Protein, Produce, …) run down the left column, the restock list picks
  # up right where they end, and each column continues into the next. A
  # column that breaks mid-section repeats that section's title at the top
  # of the next one. Two columns in portrait (the default), three in
  # landscape. A long list is drawn scaled down until it fits the page —
  # wider columns as well as shorter ones, so it re-wraps rather than just
  # shrinking. The restock part only appears when something's marked
  # Restock.

  SHOPPING_COLUMN_GAP = 18

  def shopping_section
    section_heading "Shopping list"

    groceries = @household.grocery_lists.where(week_of: @week).includes(:ingredient).left_joins(:ingredient)
                          .order(Ingredient.family_order_sql, "ingredients.ingredient ASC", :id).to_a
    restock   = RestockItem.shopping_list(@household)
    return empty_note("No grocery list has been made for this week yet, and nothing is marked Restock.") if groceries.empty? && restock.empty?

    rows    = shopping_rows(groceries, restock)
    count   = landscape?("shopping") ? 3 : 2
    top     = cursor
    factor  = 1.0
    columns = nil
    until (columns = layout_shopping_columns(rows, shopping_column_width(count, factor), top / factor, count))
      factor = (factor - 0.05).round(2)
    end

    width = shopping_column_width(count, factor)
    scale(factor, origin: [ 0, top ]) do
      # A box as tall as the (unscaled) columns: placed text boxes measure
      # their room against the bounds' bottom, and drawn shrunk, the lower
      # rows sit past the page's own (see #draw_checkbox).
      bounding_box([ 0, top ], width: bounds.width / factor, height: top / factor + 1) do
        columns.each_with_index do |column, index|
          x = index * (width + SHOPPING_COLUMN_GAP)
          y = bounds.top
          column.each { |row| y -= draw_shopping_row(row, x, y, width) }
        end
      end
    end
  end

  def shopping_column_width(count, factor)
    (bounds.width / factor - SHOPPING_COLUMN_GAP * (count - 1)) / count
  end

  # The list as rows, top to bottom: [:part, label, aside, space_before],
  # [:sub, label] (a family or store), [:cat, label] (a restock category),
  # [:item, label, detail, checked], [:gap, points].
  def shopping_rows(groceries, restock)
    rows = []

    notes, groceries = groceries.partition(&:note_only?)
    subtotal = groceries.sum { |item| item.ingredient.unit_price.to_f * item.units.to_i }
    rows << [ :part, "Groceries", (format("Estimated total: $%.2f", subtotal) if groceries.any?), 0 ]
    if groceries.empty? && notes.empty?
      rows << [ :note, "No grocery list has been made for this week yet." ]
    else
      groceries.group_by { |item| item.ingredient.family.presence || "Other" }.each do |family, items|
        rows << [ :sub, Ingredient.family_label(family) ]
        items.each do |item|
          price = item.ingredient.unit_price.present? ? format("$%.2f", item.ingredient.unit_price * item.units.to_i) : nil
          rows << [ :item, item.ingredient.ingredient, [ "#{item.units.to_i} #{'unit'.pluralize(item.units.to_i)}", price ].compact.join("  ·  "), item.checked? ]
        end
      end
      # Notes on the list ("birthday candles") — no units or price.
      if notes.any?
        rows << [ :sub, "Notes" ]
        notes.each { |item| rows << [ :item, item.note, nil, item.checked? ] }
      end
    end

    if restock.any?
      rows << [ :part, "Restock", nil, 14 ]
      restock.each do |store, categories|
        rows << [ :sub, store ]
        categories.each do |category, items|
          rows << [ :cat, category.name.upcase ]
          items.each { |item| rows << [ :item, item.name, item.brand.presence, false ] }
          rows << [ :gap, 4 ]
        end
      end
    end

    rows
  end

  # Fills the columns top to bottom, or nil if the rows need more than
  # `count` columns of `height`. A heading never sits alone at the foot of a
  # column — it moves on with the row after it — and a column that starts
  # mid-section opens with that section's titles again.
  def layout_shopping_columns(rows, width, height, count)
    columns = [ [] ]
    used    = 0
    titles  = {} # the section the next row belongs to: { sub:, cat: }

    rows.each_with_index do |row, index|
      kind  = row.first
      next if kind == :gap && used.zero?

      row_height = shopping_row_height(row, width)
      following  = rows[index + 1]
      needed     = row_height
      needed    += shopping_row_height(following, width) if shopping_heading?(row) && following && !shopping_heading?(following)

      if used.positive? && used + needed > height
        columns << []
        used = 0
        return nil if columns.size > count

        unless shopping_heading?(row) || kind == :gap
          titles.values.each do |title|
            columns.last << title
            used += shopping_row_height(title, width)
          end
        end
      end
      next if kind == :gap && used.zero?

      columns.last << row
      used += row_height

      case kind
      when :part then titles = {}
      when :sub  then titles = { sub: row }
      when :cat  then titles[:cat] = row
      end
    end

    columns
  end

  def shopping_heading?(row) = row.first.in?(%i[part sub cat])

  def shopping_row_height(row, width)
    kind, label, detail, extra = row
    case kind
    when :part then extra + serif_height(label, width, 16) + 4
    when :sub  then 6 + bold_height(label, width, 11) + 8
    when :cat  then height_of(clean(label), width:, size: 8, character_spacing: 0.5) + 3
    when :item then checkbox_height(label, detail, width)
    when :note then height_of(clean(label), width:, size: 10, style: :italic) + 8
    when :gap  then label
    end
  end

  # Draws one row with its top at `top`; returns the height it took (the
  # same as #shopping_row_height, so the layout's columns are exact).
  def draw_shopping_row(row, x, top, width)
    kind, label, detail, extra = row
    height = shopping_row_height(row, width)
    case kind
    when :part
      font(SERIF) { colored_text_box clean(label), at: [ x, top - extra ], width:, size: 16, color: SAGE_DARK }
      colored_text_box(detail, at: [ x, top - extra - 5 ], width:, align: :right, size: 11, style: :bold, color: INK) if detail
    when :sub
      label_height = bold_height(label, width, 11)
      colored_text_box clean(label), at: [ x, top - 6 ], width:, size: 11, style: :bold, color: INK
      stroke_color RULE
      stroke_horizontal_line x, x + width, at: top - 6 - label_height - 2
    when :cat
      colored_text_box clean(label), at: [ x, top ], width:, size: 8, character_spacing: 0.5, color: MUTED
    when :item
      draw_checkbox(x, top, width, height, label, detail, extra)
    when :note
      colored_text_box clean(label), at: [ x, top ], width:, size: 10, style: :italic, color: MUTED
    end
    height
  end

  # (Prawn's `font` with a block returns the font, not the block's value.)
  def serif_height(label, width, size)
    height = 0
    font(SERIF) { height = height_of(clean(label), width:, size:) }
    height
  end

  def bold_height(label, width, size)
    height = 0
    font(SANS, style: :bold) { height = height_of(clean(label), width:, size:) }
    height
  end

  def chores_section
    section_heading "Chore chart"

    Chore.auto_schedule_recurring!(@household, week_start: @week_start)
    weekly_chores = @household.weekly_chores.for_week(@week_start).includes(:assignee, chore: :chore_tasks).to_a
    return empty_note("No chores on the chart this week.") if weekly_chores.empty?

    people_legend(weekly_chores.map(&:assignee))
    return chore_board(weekly_chores) if landscape?("chores")

    chores = weekly_chores.group_by(&:scheduled_date)

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

  # ── Chore chart, landscape: the Week View's board ──
  # A row per category (all of them, plus Uncategorized when something's
  # in it — ChoresHelper#chore_board_rows), a column per day, and the
  # chores as cards in their person's color, each with a tick box and its
  # tasks underneath.

  BOARD_LABEL_WIDTH = 78
  BOARD_HEADER_HEIGHT = 18

  def chore_board(weekly_chores)
    rows = @household.chore_categories.ordered.map { |category| [ category.id, category.name ] }
    rows << [ nil, "Uncategorized" ] if weekly_chores.any? { |wc| wc.chore.chore_category_id.nil? }
    day_width = (bounds.width - BOARD_LABEL_WIDTH) / 7
    grouped   = weekly_chores.group_by { |wc| [ wc.scheduled_date, wc.chore.chore_category_id ] }

    chore_board_header(day_width)
    rows.each do |category_id, name|
      cells  = @week.map { |date| grouped[[ date, category_id ]] || [] }
      height = [ cells.map { |items| chore_card_stack_height(items, day_width - 6) }.max, 28 ].max + 6

      if cursor < height
        start_new_page
        chore_board_header(day_width)
      end

      top = cursor
      stroke_color RULE
      stroke_rectangle [ 0, top ], BOARD_LABEL_WIDTH, height
      colored_text_box clean(name), at: [ 5, top - 5 ], width: BOARD_LABEL_WIDTH - 10, size: 8.5, style: :bold, color: INK
      cells.each_with_index do |items, i|
        x = BOARD_LABEL_WIDTH + day_width * i
        stroke_color RULE
        stroke_rectangle [ x, top ], day_width, height
        draw_chore_card_stack(items, x + 3, top - 3, day_width - 6)
      end
      move_cursor_to top - height
    end

    unscheduled = weekly_chores.select { |wc| wc.scheduled_date.nil? }
    return if unscheduled.empty?

    move_down 8
    subheading "Any day"
    checkbox_columns(unscheduled.map { |wc| chore_item(wc) }, columns: 4, padded: true)
  end

  def chore_board_header(day_width)
    top = cursor
    fill_color SAGE_LIGHT
    fill_rectangle [ 0, top ], BOARD_LABEL_WIDTH + day_width * 7, BOARD_HEADER_HEIGHT
    @week.each_with_index do |date, i|
      colored_text_box date.strftime("%a %-d"), at: [ BOARD_LABEL_WIDTH + day_width * i + 5, top - 5 ],
                       width: day_width - 10, size: 8.5, style: :bold, color: SAGE_DARK
    end
    stroke_color RULE
    stroke_rectangle [ 0, top ], BOARD_LABEL_WIDTH + day_width * 7, BOARD_HEADER_HEIGHT
    move_cursor_to top - BOARD_HEADER_HEIGHT
  end

  CHORE_CARD_PAD = 4
  CHORE_CARD_BOX = 7

  # The card's name, and its tasks one per line.
  def chore_card_lines(weekly_chore)
    [ clean(weekly_chore.chore.name), weekly_chore.chore.chore_tasks.map { |task| clean("• #{task.name}") } ]
  end

  def chore_card_height(weekly_chore, width)
    name, tasks = chore_card_lines(weekly_chore)
    text_width = width - CHORE_CARD_PAD * 2 - CHORE_CARD_BOX - 4
    height = height_of(name, width: text_width, size: 8)
    height += tasks.sum { |task| height_of(task, width: text_width, size: 6.5) } + 1 if tasks.any?
    height + CHORE_CARD_PAD * 2
  end

  def chore_card_stack_height(weekly_chores, width)
    return 0 if weekly_chores.empty?

    weekly_chores.sum { |wc| chore_card_height(wc, width) } + CARD_GAP * (weekly_chores.size - 1)
  end

  def draw_chore_card_stack(weekly_chores, x, top, width)
    weekly_chores.each do |weekly_chore|
      height = chore_card_height(weekly_chore, width)
      colors = weekly_chore.assignee && Palette.print_colors(weekly_chore.assignee.color)
      done   = weekly_chore.completed?

      # A person's color, or white with a rule like the board's unassigned cards.
      fill_color colors ? colors[:card] : "ffffff"
      fill_rounded_rectangle [ x, top ], width, height, 3
      unless colors
        stroke_color RULE
        stroke_rounded_rectangle [ x, top ], width, height, 3
      end

      box_x = x + CHORE_CARD_PAD
      box_top = top - CHORE_CARD_PAD - 1
      stroke_color MUTED
      stroke_rectangle [ box_x, box_top ], CHORE_CARD_BOX, CHORE_CARD_BOX
      if done
        fill_color SAGE
        fill_rectangle [ box_x + 1.5, box_top - 1.5 ], CHORE_CARD_BOX - 3, CHORE_CARD_BOX - 3
      end

      name, tasks = chore_card_lines(weekly_chore)
      text_x = box_x + CHORE_CARD_BOX + 4
      text_width = width - CHORE_CARD_PAD * 2 - CHORE_CARD_BOX - 4
      ink = done ? MUTED : (colors ? colors[:text] : INK)
      line_top = top - CHORE_CARD_PAD
      colored_text_box name, at: [ text_x, line_top ], width: text_width, size: 8, style: :bold, color: ink
      line_top -= height_of(name, width: text_width, size: 8) + 1
      tasks.each do |task|
        colored_text_box task, at: [ text_x, line_top ], width: text_width, size: 6.5, color: done ? MUTED : (colors ? colors[:text] : MUTED)
        line_top -= height_of(task, width: text_width, size: 6.5)
      end

      top -= height + CARD_GAP
    end
    fill_color INK
  end

  # "Clean bathroom - Bob" on one line, with the chore's tasks (if any)
  # underneath: "Clean toilet · Mop floors · Wipe sink". A checkbox_columns
  # item.
  def chore_item(weekly_chore)
    label = [ weekly_chore.chore.name, weekly_chore.assignee&.name ].compact.join(" - ")
    tasks = weekly_chore.chore.chore_tasks.map(&:name).join("  ·  ").presence
    [ label, tasks, weekly_chore.completed?, weekly_chore.assignee ]
  end

  # columns: overrides the usual one (or two, once the list would run past
  # a page — @list_columns, see #fit_to_page).
  def todos_section(columns: @list_columns)
    section_heading "To-dos"

    todos = printed_todos
    return empty_note("Nothing planned for this week.") if todos.empty?

    people_legend(todos.map(&:assignee))
    checkbox_columns(todos.map do |todo|
      estimate = todo.estimated_time_to_complete.to_i.positive? ? todo.estimated_hm : nil
      [ todo.title, [ todo.assignee&.name, todo.priority_label, estimate ].compact.join("  ·  "), false, todo.assignee ]
    end, columns:, padded: true)
  end

  # The chore chart, then the to-dos, on one page (SHARED_PAGES). A
  # landscape page spreads the to-dos three across rather than leaving them
  # in a strip down the left.
  def chores_and_todos_section
    chores_section
    move_down 20
    todos_section(columns: landscape?("chores") ? 3 : @list_columns)
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
end
