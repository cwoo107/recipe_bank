require "test_helper"

# Steps and component recipes share one ordered instruction list.
class RecipeInstructionOrderTest < ActiveSupport::TestCase
  setup do
    @user    = users(:one)
    @chicken = @user.recipes.create!(title: "Chicken Teriyaki", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Teriyaki Sauce",   visibility: "private", servings: 1)
    @blend   = @user.recipes.create!(title: "Five Spice",       visibility: "private", servings: 1)
  end

  def titles(items)
    items.map { |i| i.is_a?(RecipeComponent) ? i.component_recipe.title : i.content.to_plain_text }
  end

  test "new steps and components queue up at the end of one shared list" do
    @chicken.steps.create!(content: "Make rice")
    component = @chicken.recipe_components.create!(component_recipe: @sauce)
    @chicken.steps.create!(content: "Cook chicken")

    assert_equal ["Make rice", "Teriyaki Sauce", "Cook chicken"], titles(@chicken.reload.instruction_items)
    assert_equal [1, 2, 3], @chicken.instruction_items.map(&:instruction_position)
    assert_equal 2, component.instruction_position
  end

  test "a component can be dragged in among the steps" do
    rice    = @chicken.steps.create!(content: "Make rice")
    chicken = @chicken.steps.create!(content: "Cook chicken")
    sauce   = @chicken.recipe_components.create!(component_recipe: @sauce)

    # Drop the sauce between the two steps.
    rice.update!(instruction_position: 1)
    chicken.update!(instruction_position: 2)
    sauce.update!(instruction_position: 3)
    assert_equal ["Make rice", "Cook chicken", "Teriyaki Sauce"], titles(@chicken.reload.instruction_items)

    sauce.update!(instruction_position: 2)
    chicken.update!(instruction_position: 3)
    assert_equal ["Make rice", "Teriyaki Sauce", "Cook chicken"], titles(@chicken.reload.instruction_items)
  end

  test "a step added after a component still lands last" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    step = @chicken.steps.create!(content: "Plate up")

    assert_equal 2, step.instruction_position
    assert_equal ["Teriyaki Sauce", "Plate up"], titles(@chicken.reload.instruction_items)
  end

  test "the ingredients sections follow the same order as the instructions" do
    first  = @chicken.recipe_components.create!(component_recipe: @sauce)
    second = @chicken.recipe_components.create!(component_recipe: @blend)

    assert_equal [@sauce, @blend], @chicken.reload.sections.reject(&:root?).map(&:recipe)

    first.update!(instruction_position: 99)

    assert_equal [@blend, @sauce], @chicken.reload.sections.reject(&:root?).map(&:recipe)
  end

  test "a component's own steps come through for numbering, nested ones included" do
    @sauce.steps.create!(content: "Combine and boil")
    @sauce.steps.create!(content: "Reduce by half")
    @blend.steps.create!(content: "Toast the spices")
    @sauce.recipe_components.create!(component_recipe: @blend)

    lines = @sauce.reload.sections.flat_map { |section| section.own_steps.map { |s| [section.recipe.title, s.content.to_plain_text] } }

    assert_equal [["Teriyaki Sauce", "Combine and boil"],
                  ["Teriyaki Sauce", "Reduce by half"],
                  ["Five Spice", "Toast the spices"]], lines
  end
end
