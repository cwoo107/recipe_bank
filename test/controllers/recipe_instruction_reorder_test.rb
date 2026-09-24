require "test_helper"

class RecipeInstructionReorderTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @chicken = @user.recipes.create!(title: "Chicken Teriyaki", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Teriyaki Sauce",   visibility: "private", servings: 1)
    @sauce.steps.create!(content: "Combine and boil")

    @rice    = @chicken.steps.create!(content: "Make rice")
    @cook    = @chicken.steps.create!(content: "Cook chicken")
    @component = @chicken.recipe_components.create!(component_recipe: @sauce)

    sign_in @user
  end

  test "the list posts back a mix of steps and components" do
    post reorder_instructions_recipe_url(@chicken),
         params: { order: ["step-#{@rice.id}", "component-#{@component.id}", "step-#{@cook.id}"] },
         as: :json

    assert_response :success
    assert_equal 1, @rice.reload.instruction_position
    assert_equal 2, @component.reload.instruction_position
    assert_equal 3, @cook.reload.instruction_position
  end

  test "the page renders the component as a numbered entry with sub-steps" do
    @component.update!(instruction_position: 2)
    @cook.update!(instruction_position: 3)

    get recipe_url(@chicken)

    assert_response :success
    assert_select "#recipe_steps li[data-id=?]", "step-#{@rice.id}"
    assert_select "#recipe_steps li[data-id=?]", "component-#{@component.id}" do
      assert_select ".step-number", text: "2"
      # Sub-steps number themselves 1, 2, 3 — they're told apart from the
      # main recipe's steps by the smaller neutral circle, not the number.
      assert_select ".sub-step-number", text: "1"
      assert_select "a", text: "Teriyaki Sauce"
    end
    assert_match "Combine and boil", response.body
  end

  test "ids from another recipe are ignored rather than reordered" do
    other = @user.recipes.create!(title: "Other", visibility: "private")
    theirs = other.steps.create!(content: "Not mine", instruction_position: 7)

    post reorder_instructions_recipe_url(@chicken),
         params: { order: ["step-#{theirs.id}", "step-#{@rice.id}"] }, as: :json

    assert_response :success
    assert_equal 7, theirs.reload.instruction_position, "left alone"
    assert_equal 2, @rice.reload.instruction_position
  end

  test "junk in the order list doesn't blow up" do
    post reorder_instructions_recipe_url(@chicken),
         params: { order: ["", "nonsense", "step-999999", "component-#{@component.id}"] }, as: :json

    assert_response :success
    assert_equal 4, @component.reload.instruction_position
  end

  test "someone else's recipe can't be reordered" do
    theirs = users(:three).recipes.create!(title: "Theirs", visibility: "public")
    step   = theirs.steps.create!(content: "Theirs")

    post reorder_instructions_recipe_url(theirs), params: { order: ["step-#{step.id}"] }, as: :json

    assert_response :not_found
  end
end
