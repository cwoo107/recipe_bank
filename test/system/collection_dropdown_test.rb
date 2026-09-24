require "application_system_test_case"

# The "Add to a collection" dropdown on the recipe index.
class CollectionDropdownTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user = users(:one)
    @first  = @user.recipes.create!(title: "Alpha Bake",  visibility: "private")
    @second = @user.recipes.create!(title: "Beta Braise", visibility: "private")
    @collection = @user.collections.create!(title: "Weeknights")

    login_as @user, scope: :user
  end

  # The index renders the button twice (mobile cards + desktop table); at this
  # window size only the table copy is on screen.
  def dropdown_for(recipe)
    all("[data-collection-button-recipe='#{recipe.id}']").find(&:visible?)
  end

  def menu_for(recipe) = dropdown_for(recipe).find("[data-collection-dropdown-target='menu']", visible: :all)
  def trigger_for(recipe) = dropdown_for(recipe).find("button[aria-haspopup]")

  test "the trigger names itself rather than being a bare icon" do
    visit recipes_url

    assert_equal "Add to a collection", trigger_for(@first).text
  end

  test "opening one dropdown closes any other" do
    visit recipes_url

    trigger_for(@second).click
    assert menu_for(@second).visible?

    trigger_for(@first).click
    assert menu_for(@first).visible?
    assert_not menu_for(@second).visible?, "only one dropdown should be open at a time"
  end

  test "clicking outside closes it" do
    visit recipes_url

    trigger_for(@first).click
    assert menu_for(@first).visible?

    find("h1", match: :first).click

    assert_not menu_for(@first).visible?
  end

  test "escape closes it" do
    visit recipes_url

    trigger_for(@first).click
    find("body").send_keys(:escape)

    assert_not menu_for(@first).visible?
  end

  test "adding to a collection closes the dropdown" do
    visit recipes_url

    trigger_for(@first).click
    within(menu_for(@first)) { click_button "Weeknights" }

    assert_text "Added to Weeknights"
    assert_not menu_for(@first).visible?
    assert_includes @collection.reload.recipes, @first
  end

  test "removing from a collection closes the dropdown" do
    @collection.collection_recipes.create!(recipe: @first)
    visit recipes_url

    trigger_for(@first).click
    within(menu_for(@first)) { click_button "Weeknights" }

    assert_text "Removed from Weeknights"
    assert_not menu_for(@first).visible?
    assert_not_includes @collection.reload.recipes, @first
  end

  test "the menu stays whole when the row is at the edge of the table" do
    # A long list puts the last row hard against the table's overflow-hidden
    # edge, which used to crop the dropdown.
    12.times { |i| @user.recipes.create!(title: "Filler #{i}", visibility: "private") }
    visit recipes_url

    last = @user.recipes.order(:title).last
    trigger_for(last).click
    menu = menu_for(last)

    assert menu.visible?
    assert_equal "fixed", page.evaluate_script("getComputedStyle(arguments[0]).position", menu)

    box = page.evaluate_script(<<~JS, menu)
      (() => { const r = arguments[0].getBoundingClientRect()
               return { top: r.top, left: r.left, bottom: r.bottom, right: r.right,
                        w: innerWidth, h: innerHeight } })()
    JS

    assert_operator box["top"],    :>=, 0,             "cropped at the top"
    assert_operator box["left"],   :>=, 0,             "cropped on the left"
    assert_operator box["bottom"], :<=, box["h"],      "cropped at the bottom"
    assert_operator box["right"],  :<=, box["w"],      "cropped on the right"

    # Nothing is painted over its centre — i.e. it isn't clipped away.
    assert page.evaluate_script(<<~JS, menu), "the menu is not the topmost element at its centre"
      (() => { const m = arguments[0], r = m.getBoundingClientRect()
               const hit = document.elementFromPoint((r.left + r.right) / 2, (r.top + r.bottom) / 2)
               return m.contains(hit) })()
    JS
  end

  test "the menu flips above the trigger when there is no room below" do
    visit recipes_url

    trigger = trigger_for(@first)
    page.execute_script(<<~JS, trigger)
      const wrapper = arguments[0].closest('[data-controller="collection-dropdown"]')
      wrapper.style.position = 'fixed'
      wrapper.style.top = (window.innerHeight - 40) + 'px'
      wrapper.style.left = '200px'
    JS

    trigger.click
    menu = menu_for(@first)

    assert menu.visible?
    placement = page.evaluate_script(<<~JS, menu)
      (() => { const m = arguments[0].getBoundingClientRect()
               const t = arguments[0].closest('[data-controller="collection-dropdown"]')
                          .querySelector('button[aria-haspopup]').getBoundingClientRect()
               return { menuBottom: m.bottom, triggerTop: t.top } })()
    JS

    assert_operator placement["menuBottom"], :<=, placement["triggerTop"] + 1,
                    "the menu should sit above the trigger"
  end
end
