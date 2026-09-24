require "test_helper"

# Recipes used as ingredients of other recipes.
class RecipeComponentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @chicken = recipe("Chicken", servings: 4)
    @sauce   = recipe("Lemon Garlic Sauce", servings: 1)
    @blend   = recipe("Spice Blend", servings: 1)
  end

  def recipe(title, servings: 4)
    @user.recipes.create!(title: title, visibility: "private", servings: servings)
  end

  # 100 cal per 100g keeps grams in == calories out.
  def ingredient(name)
    ing = Ingredient.create!(ingredient: name, family: "produce")
    ing.create_nutrition_fact!(serving_size: 100, serving_unit: "g", calories: 100,
                               protein: 10, total_fat: 0, total_carb: 0)
    ing
  end

  def add_line(recipe, name, grams)
    recipe.recipe_ingredients.create!(ingredient: ingredient(name), quantity: grams, unit: "g")
  end

  # ── The link ──────────────────────────────────────────────────────────────

  test "a recipe can be added as a component of another" do
    component = @chicken.recipe_components.create!(component_recipe: @sauce)

    assert_equal 1.0, component.multiplier
    assert_equal [@sauce], @chicken.reload.component_recipes
    assert_equal [@chicken], @sauce.reload.used_by_recipes
  end

  test "a recipe can't be its own component" do
    component = @chicken.recipe_components.build(component_recipe: @chicken)

    refute component.valid?
    assert_includes component.errors.full_messages.to_sentence, "can't be the recipe itself"
  end

  test "a loop is rejected however long the chain" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    @sauce.recipe_components.create!(component_recipe: @blend)

    loopback = @blend.recipe_components.build(component_recipe: @chicken)

    refute loopback.valid?, "blend -> chicken would close chicken -> sauce -> blend"
    assert_includes loopback.errors.full_messages.to_sentence, "circular"
  end

  test "the same component can't be added twice" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    duplicate = @chicken.recipe_components.build(component_recipe: @sauce)

    refute duplicate.valid?
  end

  test "a multiplier has to be a positive amount" do
    assert @chicken.recipe_components.build(component_recipe: @sauce, multiplier: 0.5).valid?
    refute @chicken.recipe_components.build(component_recipe: @sauce, multiplier: 0).valid?
    refute @chicken.recipe_components.build(component_recipe: @sauce, multiplier: -1).valid?
  end

  test "deleting a component recipe detaches it from the recipes using it" do
    @chicken.recipe_components.create!(component_recipe: @sauce)

    assert_difference("RecipeComponent.count", -1) { @sauce.destroy! }
    assert_empty @chicken.reload.recipe_components
  end

  # ── Resolving ─────────────────────────────────────────────────────────────

  test "sections list the recipe then everything it pulls in, depth first" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    @sauce.recipe_components.create!(component_recipe: @blend)

    sections = @chicken.sections

    assert_equal [@chicken, @sauce, @blend], sections.map(&:recipe)
    assert_equal [0, 1, 2], sections.map(&:depth)
    assert sections.first.root?
  end

  test "multipliers compound down the chain" do
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)
    @sauce.recipe_components.create!(component_recipe: @blend, multiplier: 2.0)

    assert_equal [1.0, 0.5, 1.0], @chicken.sections.map(&:multiplier)
  end

  test "component ingredient quantities come through scaled" do
    add_line(@chicken, "Chicken breast", 400)
    add_line(@sauce, "Cream", 200)
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    lines = @chicken.all_ingredients

    assert_equal ["Chicken breast", "Cream"], lines.map { |l| l.ingredient.ingredient }
    assert_equal [400.0, 100.0], lines.map(&:quantity)
    assert_equal [false, true], lines.map(&:scaled?)
  end

  test "the component's own page is unaffected by how others scale it" do
    add_line(@sauce, "Cream", 200)
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    assert_equal [200.0], @sauce.all_ingredients.map(&:quantity)
  end

  test "resolving terminates even if a loop somehow exists in the data" do
    a = @chicken.recipe_components.create!(component_recipe: @sauce)
    # Force a loop past the validation, the way bad data would look.
    RecipeComponent.new(parent_recipe: @sauce, component_recipe: @chicken).save!(validate: false)

    assert_equal [@chicken, @sauce], @chicken.sections.map(&:recipe)
    assert a.persisted?
  end

  # ── What it feeds ─────────────────────────────────────────────────────────

  test "nutrition counts the components" do
    add_line(@chicken, "Chicken breast", 400)
    add_line(@sauce, "Cream", 200)

    assert_equal 400, @chicken.total_calories

    @chicken.recipe_components.create!(component_recipe: @sauce)
    assert_equal 600, @chicken.reload.total_calories
    assert_equal 60, @chicken.total_protein
  end

  test "a half batch contributes half its nutrition" do
    add_line(@sauce, "Cream", 200)
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    assert_equal 100, @chicken.reload.total_calories
  end

  test "editing the component updates every recipe built on it" do
    add_line(@chicken, "Chicken breast", 400)
    cream = add_line(@sauce, "Cream", 200)
    @chicken.recipe_components.create!(component_recipe: @sauce)

    assert_equal 600, @chicken.reload.total_calories

    cream.update!(quantity: 400)

    assert_equal 800, @chicken.reload.total_calories, "the link is live, not a copy"
  end

  test "a meal's cost counts the components, scaled both ways" do
    priced = Ingredient.create!(ingredient: "Cream", family: "dairy", unit_price: 4.0, unit_servings: 4)
    @sauce.recipe_ingredients.create!(ingredient: priced, quantity: 1, unit: "cup")
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    meal = Meal.create!(recipe: @chicken.reload, user: @user, household: @user.household,
                        meal_name: "Dinner", date: Date.current, servings: 8)

    # 4.0 / 4 servings-per-unit = 1.0 per line, x2 meal servings multiplier.
    assert_in_delta 2.0, meal.total_cost, 0.001
  end

  test "copying a recipe keeps its components pointed at the same recipes" do
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    copy = @chicken.duplicate_for(@user, title: "Chicken (copy)")

    assert_equal [@sauce], copy.component_recipes
    assert_equal [0.5], copy.recipe_components.map(&:multiplier)
  end
end
