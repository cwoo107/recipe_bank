require "application_system_test_case"

# Dragging a component recipe into place among the instructions.
class RecipeInstructionDragTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user    = users(:one)
    @chicken = @user.recipes.create!(title: "Chicken Teriyaki", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Teriyaki Sauce",   visibility: "private", servings: 1)
    @sauce.steps.create!(content: "Combine ingredients and boil")
    @sauce.steps.create!(content: "Reduce by half")

    @rice      = @chicken.steps.create!(content: "Make rice")
    @cook      = @chicken.steps.create!(content: "Cook chicken")
    @component = @chicken.recipe_components.create!(component_recipe: @sauce)

    login_as @user, scope: :user
  end

  # SortableJS's own gesture handling is not our code, and it doesn't respond
  # to synthetic events or Selenium's Actions API here. This reorders the DOM
  # the way a drop does and then fires the drop handler, which is the part we
  # wrote: renumbering, and posting the new order.
  def simulate_drop(moved_id, before_id)
    page.execute_script(<<~JS, moved_id, before_id)
      const [movedId, beforeId] = arguments
      const list = document.getElementById("instruction_list")
      list.insertBefore(list.querySelector(`[data-id="${movedId}"]`),
                        list.querySelector(`[data-id="${beforeId}"]`))
      window.Stimulus.getControllerForElementAndIdentifier(list, "sortable").end()
    JS
  end

  def numbers
    all("#instruction_list > li").map { |li| li.find(".step-number").text }
  end

  test "the component sits in the list as a numbered entry with sub-steps" do
    visit recipe_url(@chicken)

    assert_equal %w[1 2 3], numbers
    within "#recipe_steps" do
      within "li[data-id='component-#{@component.id}']" do
        assert_equal "3", find(".step-number").text
        assert_equal %w[1 2], all(".sub-step-number").map(&:text)
        assert_text "Combine ingredients and boil"
      end
    end
  end

  test "dragging the component up renumbers it and its sub-steps, and sticks" do
    visit recipe_url(@chicken)
    click_button "Edit"

    simulate_drop("component-#{@component.id}", "step-#{@rice.id}")

    # Renumbered in place, without a reload.
    within "li[data-id='component-#{@component.id}']" do
      assert_equal "1", find(".step-number").text
      # Sub-steps keep their own numbering wherever the component lands.
      assert_equal %w[1 2], all(".sub-step-number").map(&:text)
    end

    # And persisted.
    assert_equal 1, @component.reload.instruction_position
    assert_equal 2, @rice.reload.instruction_position
    assert_equal 3, @cook.reload.instruction_position

    visit recipe_url(@chicken)
    assert_equal ["component-#{@component.id}", "step-#{@rice.id}", "step-#{@cook.id}"],
                 all("#instruction_list > li").map { |li| li["data-id"] }
  end
end
