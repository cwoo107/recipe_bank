require "test_helper"

class IngredientTest < ActiveSupport::TestCase
  test "capitalizes the ingredient name on save" do
    ingredient = Ingredient.create!(ingredient: "extra virgin olive OIL")
    assert_equal "Extra virgin olive oil", ingredient.ingredient
  end

  test "strips surrounding whitespace while capitalizing" do
    ingredient = Ingredient.create!(ingredient: "  chicken breast  ")
    assert_equal "Chicken breast", ingredient.ingredient
  end

  class CopyForTest < ActiveSupport::TestCase
    setup do
      @ours   = households(:one)
      @theirs = households(:two)
      @alice  = users(:one)
      @beans  = @theirs.ingredients.create!(ingredient: "Black beans", brand: "Goya", family: "protein",
                                           unit_price: 1.5, unit_servings: 3, favorite: true)
      @beans.create_nutrition_fact!(serving_size: 130, serving_unit: "g", calories: 110,
                                    protein: 7, total_fat: 0.5, total_carb: 20)
      @beans.tags << users(:three).tags.create!(tag: "Pantry", color: "#5f734c")
    end

    test "an ingredient already in the household is returned as-is" do
      assert_equal @beans, @beans.copy_for(@theirs)
    end

    test "another household's ingredient is copied in, with its nutrition and tags" do
      copy = assert_difference("Ingredient.count", 1) { @beans.copy_for(@ours, user: @alice) }

      assert_equal @ours, copy.household
      assert_equal @alice, copy.created_by
      assert_equal @beans, copy.source_ingredient
      assert_equal ["Black beans", "Goya", "protein", 1.5, 3],
                   [copy.ingredient, copy.brand, copy.family, copy.unit_price, copy.unit_servings]
      refute copy.favorite, "favorites are the household's own choice"
      assert_equal 110, copy.nutrition_fact.calories
      refute_equal @beans.nutrition_fact, copy.nutrition_fact
      assert_equal [["Pantry", @alice.id]], copy.tags.map { |t| [t.tag, t.user_id] }
    end

    test "copying the same ingredient twice reuses the first copy" do
      first = @beans.copy_for(@ours)
      first.update!(ingredient: "Beans, black") # renamed since — still the same copy
      assert_no_difference("Ingredient.count") { assert_equal first, @beans.copy_for(@ours) }
    end

    test "a same-named, same-brand ingredient the household already has is reused" do
      mine = @ours.ingredients.create!(ingredient: "black BEANS", brand: "goya")
      assert_no_difference("Ingredient.count") { assert_equal mine, @beans.copy_for(@ours) }
    end

    test "a different brand of the same thing gets its own copy" do
      @ours.ingredients.create!(ingredient: "Black beans", brand: "Bush's")
      assert_difference("Ingredient.count", 1) { @beans.copy_for(@ours) }
    end

    test "deleting the original leaves the other household's recipe intact" do
      recipe = @alice.recipes.create!(title: "Burrito bowls")
      recipe.recipe_ingredients.create!(ingredient: @beans.copy_for(@ours), quantity: 1, unit: "cup")

      @beans.destroy!

      assert_equal ["Black beans"], recipe.reload.ingredients.map(&:ingredient)
    end
  end

  test "only members of the owning household can edit an ingredient" do
    ingredient = households(:one).ingredients.create!(ingredient: "Salt")

    assert ingredient.editable_by?(users(:one))
    assert ingredient.editable_by?(users(:two)), "household members share the library"
    refute ingredient.editable_by?(users(:three))
    refute ingredient.editable_by?(nil)
  end

  test "an unowned catalog ingredient can't be edited by anyone" do
    refute Ingredient.create!(ingredient: "Pepper").editable_by?(users(:one))
  end

  test "a recipe can't use another household's ingredient" do
    recipe = users(:one).recipes.create!(title: "Toast")
    line   = recipe.recipe_ingredients.build(ingredient: households(:two).ingredients.create!(ingredient: "Butter"))

    refute line.valid?
    assert_includes line.errors[:ingredient], "must be one of your household's ingredients"
  end
end
