require "test_helper"
require Rails.root.join("db/migrate/20260930120100_localize_recipe_ingredients")

# The data migration that moves recipes off other households' ingredients.
class LocalizeRecipeIngredientsTest < ActiveSupport::TestCase
  setup do
    @alice  = users(:one)   # household one
    @carol  = users(:three) # household two
    @garlic = households(:two).ingredients.create!(ingredient: "Garlic", created_by: @carol)
    @garlic.create_nutrition_fact!(serving_size: 3, serving_unit: "g", calories: 4)
    @garlic.tags << @carol.tags.create!(tag: "Aromatic", color: "#5f734c")

    @recipe = @alice.recipes.create!(title: "Aglio e olio")
    # How recipes were saved before ingredients were per-household.
    @line = @recipe.recipe_ingredients.new(ingredient: @garlic, quantity: 3, unit: "clove")
    @line.save!(validate: false)
    @grocery = households(:one).grocery_lists.create!(ingredient: @garlic, user: @alice, units: 1)
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { LocalizeRecipeIngredients.new.up }
  end

  test "each recipe gets its own household's copy, with nutrition and tags" do
    migrate

    copy = @line.reload.ingredient
    assert_equal households(:one), copy.household
    assert_equal @garlic, copy.source_ingredient
    assert_equal @alice, copy.created_by
    assert_equal 4, copy.nutrition_fact.calories
    assert_equal [["Aromatic", @alice.id]], copy.tags.map { |t| [t.tag, t.user_id] }
    assert_equal copy, @grocery.reload.ingredient, "the grocery list follows the copy"
    assert_equal households(:two), @garlic.reload.household, "the original stays with its household"
  end

  test "an ingredient the household already has is reused instead of copied" do
    ours = households(:one).ingredients.create!(ingredient: "garlic")

    assert_no_difference("Ingredient.count") { migrate }
    assert_equal ours, @line.reload.ingredient
  end

  test "lines sharing an ingredient share one copy" do
    other = @alice.recipes.create!(title: "Garlic bread")
    other.recipe_ingredients.new(ingredient: @garlic, quantity: 2).save!(validate: false)

    assert_difference("Ingredient.count", 1) { migrate }
    assert_equal 1, Ingredient.where(source_ingredient: @garlic).count
  end

  test "running it again changes nothing" do
    migrate

    assert_no_difference(["Ingredient.count", "NutritionFact.count", "IngredientTag.count"]) { migrate }
  end

  test "lines already in the right household, and ownerless recipes, are left alone" do
    ours      = households(:one).ingredients.create!(ingredient: "Salt")
    salted    = @recipe.recipe_ingredients.create!(ingredient: ours, quantity: 1)
    orphan    = recipes(:one).recipe_ingredients.new(ingredient: @garlic, quantity: 1)
    orphan.save!(validate: false)

    migrate

    assert_equal ours, salted.reload.ingredient
    assert_equal @garlic, orphan.reload.ingredient
  end
end
