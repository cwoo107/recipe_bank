# Screenshots for the marketing pages (app/assets/images/marketing), taken
# from a made-up household so no real family's data ends up on the site.
#
#   bin/rails marketing:demo_household   # once — builds "The Parkers" in the dev database
#   bin/rails marketing:screenshots      # headless Chrome → PNG + WebP, light and dark
#
# ONLY=chores,chores-mobile reshoots just those; THEME=dark just one theme.
#
# Development only. The demo household is left in place; RESET=1 on
# demo_household deletes it (and only it) and builds it fresh.
namespace :marketing do
  desc "Build the made-up household the marketing screenshots are taken from"
  task demo_household: :environment do
    abort "Development only." unless Rails.env.development?

    if (existing = User.find_by(email: MarketingDemo::EMAIL))
      abort "The demo household already exists. RESET=1 deletes it and builds it again." unless ENV["RESET"] == "1"

      existing.destroy!
      puts "Deleted the old demo household."
    end

    MarketingDemo.build!
    puts "Built the demo household (#{MarketingDemo::EMAIL})."
  end

  desc "Screenshot the demo household's pages for the marketing site"
  task screenshots: :environment do
    abort "Development only." unless Rails.env.development?

    user = User.find_by(email: MarketingDemo::EMAIL) or abort "Run bin/rails marketing:demo_household first."
    MarketingScreenshots.new(user).run
  end
end

module MarketingDemo
  EMAIL = "demo@homemakershaven.invalid".freeze

  RECIPES = {
    breakfast: [ "Pancakes", "Overnight Oats", "Egg & Cheese Breakfast Burritos", "Scrambled Eggs & Toast", "Waffles", "Egg Muffins", "Oatmeal" ],
    lunch:     [ "Turkey Sandwiches", "Chicken Caesar Salad", "Quesadillas", "Tomato Soup", "BLT Sandwiches", "Pasta Salad", "Chicken Salad Sandwiches" ],
    dinner:    [ "Chicken Fajitas", "Spaghetti and Meatballs", "Beef Tacos", "Chicken Stir-Fry", "Shepherd's Pie", "Lasagna", "BBQ Chicken" ]
  }.freeze

  TODOS = [
    # title, priority, minutes, status, tags
    [ "Schedule Maya's dentist cleaning", :high,   20,  "in_progress", %w[Kids] ],
    [ "Return library books",             :medium, 30,  "in_progress", %w[Errands] ],
    [ "Replace the furnace filter",       :urgent, 30,  "in_progress", %w[House] ],
    [ "Sign Leo up for spring soccer",    :high,   30,  "in_progress", %w[Kids] ],
    [ "Clean out the garage",             :medium, 180, "in_progress", %w[House] ],
    [ "Renew car registration",           :high,   30,  "done",        %w[Errands Paperwork] ],
    [ "Order Grandma's birthday gift",    :medium, 30,  "done",        %w[Family] ],
    [ "Plant the fall bulbs",             :low,    90,  "todo",        %w[Yard] ],
    [ "Paint the guest room",             :low,    480, "todo",        %w[House] ],
    [ "Book the summer cabin",            :medium, 45,  "todo",        %w[Family] ],
    [ "Sort the kids' outgrown clothes",  :low,    120, "todo",        %w[Kids] ]
  ].freeze

  RESTOCK = {
    "Pantry"               => [ [ "Coffee beans", "Peet's Major Dickason's", "Costco", true ], [ "Olive oil", "Kirkland", "Costco", false ],
                                [ "Peanut butter", "Jif", "Target", true ], [ "Rice", "Lundberg", "Costco", false ], [ "Pasta", "Barilla", "Target", false ] ],
    "Kitchen"              => [ [ "Dish soap", "Dawn", "Target", true ], [ "Paper towels", "Bounty", "Costco", true ],
                                [ "Dishwasher pods", "Cascade", "Costco", false ], [ "Trash bags", "Glad", "Amazon", false ] ],
    "Bathrooms"            => [ [ "Toilet paper", "Charmin", "Costco", true ], [ "Hand soap", "Method", "Target", false ], [ "Toothpaste", "Crest", "Target", true ] ],
    "Laundry Room"         => [ [ "Laundry detergent", "Tide Free & Gentle", "Amazon", false ], [ "Dryer sheets", "Bounce", "Target", false ] ],
    "Refrigerator/Freezer" => [ [ "Milk", "Horizon Organic", nil, true ], [ "Butter", "Kerrygold", "Costco", false ], [ "Frozen berries", "Kirkland", "Costco", false ] ]
  }.freeze

  # Three synced calendars, so the shots show how they come together.
  CALENDARS = {
    family: { name: "Parker Family", provider: "google",  color: "seafoam" },
    work:   { name: "Sam — Work",    provider: "outlook", color: "honey" },
    sports: { name: "Kids' Sports",  provider: "ical",    color: "dusty-rose" }
  }.freeze

  EVENTS = [
    # calendar, day offset from week start, title, hour, minutes long (no hour: all day)
    [ :sports, 0, "Leo — soccer practice",     17, 90 ], [ :family, 1, "Maya — piano lesson", 16, 45 ], [ :sports, 2, "Leo — soccer practice", 17, 90 ],
    [ :family, 2, "Parent–teacher conference", 15, 30 ], [ :family, 3, "Book club",            19, 120 ], [ :family, 4, "Movie night", 19, 120 ],
    [ :sports, 5, "Leo's soccer game",         14, 90 ], [ :family, 5, "Farmers market",       9, 60 ], [ :family, 6, "Dinner at Grandma's", 17, 150 ],
    [ :sports, 1, "Maya — swim practice",      17, 60 ], [ :sports, 3, "Maya — swim practice", 17, 60 ],
    [ :work,   0, "Quarterly planning",        13, 90 ], [ :work,   1, "Client call",         13, 60 ], [ :work,   2, "1:1 with Dana",       12, 30 ],
    [ :work,   3, "Design review",             14, 60 ], [ :work,   4, "Team lunch",          12, 60 ],
    # A full Saturday, for the phone screenshot's day view.
    [ :family, 5, "Maya — birthday party",     11, 120 ], [ :family, 5, "Grocery pickup",      16, 30 ], [ :family, 5, "Date night",          19, 150 ],
    [ :family, 4, "Teacher in-service — no school", nil, nil ]
  ].freeze

  def self.build!
    library = Recipe.publicly_visible.where(featured: true).or(Recipe.publicly_visible).index_by(&:title)

    ActiveRecord::Base.transaction do
      user = User.create!(email: EMAIL, password: SecureRandom.base58(24), household_family_name: "The Parkers")
      household = user.household
      household.update!(time_zone: "Central Time (US & Canada)", family_size: 4, comped_until: 10.years.from_now,
                        todo_minutes_per_week: 8 * 60)
      household.owner_member.update!(name: "Sam", color: "olive")
      jordan = household.invite_member(name: "Jordan", color: "seafoam")
      jordan.update!(role: :admin)
      maya = household.invite_member(name: "Maya", color: "honey").tap { |member| member.update!(child: true) }
      leo  = household.invite_member(name: "Leo", color: "mauve").tap { |member| member.update!(child: true) }
      people = [ household.owner_member, jordan, maya, leo ]

      week = Date.current.beginning_of_week(household.week_start_symbol)

      # Recipes and a full week of meals.
      copies = RECIPES.transform_values do |titles|
        titles.filter_map { |title| library[title]&.duplicate_for(user) }
      end
      7.times do |day|
        RECIPES.each_key do |meal|
          recipe = copies[meal][day % copies[meal].size] or next
          household.meals.create!(user:, date: week + day, meal_name: meal.to_s.capitalize, recipe:, servings: 4)
        end
      end

      # To-dos, some planned for this week and a couple already done.
      TODOS.each_with_index do |(title, priority, minutes, status, tags), index|
        todo = household.todos.create!(user:, title:, priority:, estimated_time_to_complete: minutes,
                                       assignee: people[index % 2], tag_names: tags.join(", "))
        todo.move_to_column!(status)
        todo.apply_status_side_effects!("todo", week:)
      end

      # Chores from the template library, handed out round the family.
      %w[standard_cleaning chores yard].each { |key| ChoreTemplate.all.find { |template| template.key == key }&.add_to!(household) }
      household.chores.order(:id).each_with_index do |chore, index|
        attributes = { assignee: people[index % people.size] }
        attributes[:default_weekday] = index % 7 if chore.frequency.in?(Chore::RECURRING_FREQUENCIES)
        chore.update!(attributes)
      end
      Chore.auto_schedule_recurring!(household, week_start: week)
      household.weekly_chores.where(week_start: week, scheduled_date: ...Date.current).find_each(&:mark_complete!)

      # Restock checklist, with stores, and a few things running low.
      RESTOCK.each do |category_name, items|
        category = household.restock_categories.find_or_create_by!(name: category_name)
        items.each_with_index do |(name, brand, store, low), index|
          item = household.restock_items.create!(user:, restock_category: category, name:, brand:, store_names: store.to_s)
          # Checked this week — all but the odd one still waiting for a look.
          if low then item.mark_restock!
          elsif index != 3 then item.mark_stocked!
          end
        end
      end

      # The family, work and kids' sports calendars for the week. No iCal
      # links, so nothing tries to sync them (the link is otherwise required).
      sources = CALENDARS.transform_values do |attributes|
        household.calendar_sources.new(user:, **attributes).tap do |source|
          source.last_synced_at = Time.current
          source.save!(validate: false)
        end
      end
      Time.use_zone(household.zone) do
        EVENTS.each do |calendar, offset, title, hour, minutes|
          events = sources.fetch(calendar).calendar_events
          day = week + offset
          if hour
            starts = Time.zone.local(day.year, day.month, day.day, hour)
            events.create!(household:, user:, title:, starts_at: starts, ends_at: starts + minutes.minutes)
          else
            events.create!(household:, user:, title:, all_day: true,
                           starts_at: day.beginning_of_day, ends_at: day.end_of_day)
          end
        end
      end
    end
  end
end

class MarketingScreenshots
  OUTPUT = Rails.root.join("app/assets/images/marketing")
  WIDTH  = 1300
  MAX_HEIGHT = 1700 # CSS pixels — a long page is cut off here

  # Phone-sized versions ("<name>-mobile"), shown to visitors on phones.
  MOBILE = { width: 390, max_height: 844, scale: 3 } # an iPhone's screen
  MOBILE_PAGES = %w[meal-planning chores calendar plan-week].freeze

  # Theme → file name suffix ("<name>-dark"). THEME=dark shoots just one.
  THEMES = { "light" => "", "dark" => "-dark" }.freeze

  # Image name → the page it's taken from.
  def pages(week)
    {
      "meal-planning" => "/meals",
      "grocery-list"  => "/grocery_list",
      "todo-list"     => "/todos",
      "calendar"      => "/calendar/week",
      "chores"        => "/weekly_chores",
      "restock"       => "/restock_items",
      "plan-week"     => "/plan-week/todos?week=#{week}",
      "recipe-detail" => "/recipes/#{@user.recipes.find_by(title: 'Chicken Fajitas')&.id || @user.recipes.first.id}"
    }
  end

  def initialize(user)
    @user = user
  end

  def run
    require "capybara"
    require "selenium-webdriver"

    Capybara.register_driver(:marketing_chrome) do |app|
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless=new")
      # Taller than any shot, so nothing has to resize (and redraw) mid-capture.
      options.add_argument("--window-size=#{WIDTH},#{MAX_HEIGHT + 200}")
      options.add_argument("--force-device-scale-factor=2")
      options.add_argument("--hide-scrollbars")
      options.add_argument("--force-prefers-reduced-motion")
      Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
    end
    Capybara.server = :puma, { Silent: true }
    Capybara.app = Rails.application
    session = Capybara::Session.new(:marketing_chrome, Rails.application)

    # Sign in through the form, with a throwaway password made for this run.
    password = SecureRandom.base58(24)
    @user.update!(password:)
    session.visit "/users/sign_in"
    session.fill_in "Email", with: @user.email
    session.fill_in "Password", with: password
    session.find("input[type=submit][value='Sign in']").click
    session.assert_no_current_path("/users/sign_in")

    household = @user.household
    week = Date.current.beginning_of_week(household.week_start_symbol)

    # The grocery list comes from the meal plan — generate it the way a
    # person would, from its button.
    if household.grocery_lists.where(week_of: week...(week + 7)).none?
      session.visit "/grocery_list"
      session.click_on "Auto generate list"
      session.find("[data-action='click->turbo-confirm#accept']").click
      session.assert_no_text("Subtotal\n$0.00", wait: 10)
      sleep 1
    end

    only = ENV["ONLY"].to_s.split(",")
    themes = ENV["THEME"].present? ? THEMES.slice(*ENV["THEME"].split(",")) : THEMES
    original_theme = @user.theme
    browser = session.driver.browser

    # Each theme in turn — the marketing pages show the dark set to visitors
    # viewing them in dark mode (MarketingHelper#marketing_screenshot).
    themes.each do |theme, suffix|
      @theme = theme
      @user.update_column(:theme, theme)

      browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
      pages(week).each do |name, path|
        next if only.any? && !only.include?(name)

        shoot(session, "#{name}#{suffix}", path)
      end

      # Then on a phone: Chrome's mobile emulation, so the pages lay out (and
      # their media queries match) as on one.
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: MOBILE[:width], height: MOBILE[:max_height] + 200,
                                                                deviceScaleFactor: MOBILE[:scale], mobile: true)
      browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true)
      pages(week).slice(*MOBILE_PAGES).each do |name, path|
        next if only.any? && !only.include?("#{name}-mobile")

        # A week of calendar is too cramped on a phone — show its busiest day,
        # from an hour before its first event.
        if name == "calendar"
          day, first_hour = busiest_day(household, week)
          path = "/calendar/day?date=#{day}"
          @scroll_to_hour = [ first_hour - 1, 0 ].max
        end
        shoot(session, "#{name}-mobile#{suffix}", path, max_height: MOBILE[:max_height])
      end
    end
  ensure
    @user.update_column(:theme, original_theme) if original_theme
    session&.driver&.quit
  end

  private

  # The day (in the household's zone) with the most timed events, and the
  # hour its first one starts.
  def busiest_day(household, week)
    Time.use_zone(household.time_zone.presence || Time.zone) do
      day, events = household.calendar_events.where(all_day: false)
                             .where(starts_at: week.in_time_zone...(week + 7).in_time_zone)
                             .group_by { |event| event.starts_at.in_time_zone.to_date }
                             .max_by { |_day, day_events| day_events.size }
      day ? [ day, events.map { |event| event.starts_at.in_time_zone.hour }.min ] : [ week, 9 ]
    end
  end

  def shoot(session, name, path, max_height: MAX_HEIGHT)
    session.visit path
    sleep 1 # Stimulus settles

    # Just the page itself: no navbar, banners or planning bar.
    session.execute_script(<<~JS)
      document.querySelectorAll("body > nav, body > header, #trial_banner, [id^=plan_week_bar], #flash, .fixed").forEach(el => el.style.display = "none")
      document.documentElement.style.colorScheme = "#{@theme}"
    JS
    sleep 2 # charts animate in

    # The calendar opens on early morning; show the busy afternoon and evening
    # (or, for the day view, from the hour set for it).
    fraction = name.start_with?("calendar-mobile") ? @scroll_to_hour / 24.0 : 0.4
    session.execute_script(<<~JS) if name.start_with?("calendar")
      document.querySelectorAll("main *").forEach(el => {
        if (el.scrollHeight > el.clientHeight + 50 && getComputedStyle(el).overflowY.match(/auto|scroll/)) el.scrollTop = el.scrollHeight * #{fraction}
      })
    JS
    sleep 0.5

    # Through Chrome's DevTools, clipped to the page's content (and no
    # further down than max_height, which the window is tall enough for).
    rect = session.evaluate_script(<<~JS)
      (() => { const r = document.querySelector("main").getBoundingClientRect()
               return { x: r.left + window.scrollX, y: r.top + window.scrollY, width: r.width, height: r.height } })()
    JS
    shot = session.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: false,
                                              clip: { x: rect["x"], y: rect["y"], width: rect["width"],
                                                      height: [ rect["height"], max_height ].min, scale: 1 })
    png = OUTPUT.join("#{name}.png")
    File.binwrite(png, Base64.decode64(shot["data"]))
    system("cwebp", "-quiet", "-q", "82", png.to_s, "-o", OUTPUT.join("#{name}.webp").to_s, exception: true)
    puts "#{name}: #{png}"
  end
end
