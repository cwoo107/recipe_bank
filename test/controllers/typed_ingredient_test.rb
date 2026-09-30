require "test_helper"

# Typing a name that isn't in the household's library into the recipe page's
# ingredient picker: the ingredient is created along with the recipe line,
# with no separate form.
class TypedIngredientTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Cookies", visibility: "private", servings: 24)
    sign_in @user
  end

  test "a new name creates the ingredient and puts it on the recipe" do
    assert_difference([ "Ingredient.count", "RecipeIngredient.count" ], 1) do
      assert_enqueued_with(job: IngredientEnrichmentJob) do
        add_line new_ingredient_name: "  chocolate   chips ", quantity: 2, unit: "cup"
      end
    end

    line = @recipe.recipe_ingredients.last
    ingredient = line.ingredient
    assert_equal "Chocolate chips", ingredient.ingredient
    assert_equal households(:one), ingredient.household
    assert_equal @user, ingredient.created_by
    assert_nil ingredient.family.presence, "family is left for the AI to work out, like the create form"
    assert_equal [ 2.0, "cup" ], [ line.quantity, line.unit ]
  end

  test "the line and a note about the new ingredient stream back in place" do
    add_line new_ingredient_name: "chocolate chips", quantity: 1, as: :turbo_stream

    assert_response :success
    assert_match 'target="recipe_ingredients_section"', response.body
    assert_match 'target="new_ingredient"', response.body
    assert_match "Added Chocolate chips to your ingredients", response.body
  end

  test "a name already in the library, in any case, reuses that ingredient" do
    existing = households(:one).ingredients.create!(ingredient: "Chocolate chips")

    assert_no_difference("Ingredient.count") do
      assert_no_enqueued_jobs(only: IngredientEnrichmentJob) do
        add_line new_ingredient_name: "CHOCOLATE CHIPS", quantity: 1
      end
    end
    assert_equal existing, @recipe.recipe_ingredients.last.ingredient
  end

  test "another household's ingredient of the same name isn't borrowed" do
    theirs = households(:two).ingredients.create!(ingredient: "Chocolate chips")

    add_line new_ingredient_name: "chocolate chips", quantity: 1

    ingredient = @recipe.recipe_ingredients.last.ingredient
    assert_not_equal theirs, ingredient
    assert_equal households(:one), ingredient.household
  end

  test "a picked ingredient wins over any typed name" do
    picked = households(:one).ingredients.create!(ingredient: "Butter")

    assert_no_difference("Ingredient.count") do
      add_line ingredient_id: picked.id, new_ingredient_name: "Buttr", quantity: 1
    end
    assert_equal picked, @recipe.recipe_ingredients.last.ingredient
  end

  test "nothing picked and nothing typed adds nothing" do
    assert_no_difference([ "Ingredient.count", "RecipeIngredient.count" ]) do
      add_line new_ingredient_name: "   ", quantity: 1
    end
    assert_redirected_to recipe_url(@recipe)
    assert_equal "Failed to add ingredient.", flash[:alert]
  end

  test "a name in the shared catalog is copied in, prices and nutrition included" do
    catalog = Ingredient.create!(ingredient: "Chocolate chips", family: "fat", unit_price: 3.49, unit_servings: 24)
    catalog.create_nutrition_fact!(serving_size: 1, serving_unit: "tbsp", calories: 70, protein: 1, total_fat: 4, total_carb: 9)

    assert_difference("Ingredient.count", 1) do
      assert_no_enqueued_jobs(only: IngredientEnrichmentJob) do
        add_line new_ingredient_name: "chocolate CHIPS", quantity: 2, unit: "tbsp", as: :turbo_stream
      end
    end

    copy = @recipe.recipe_ingredients.last.ingredient
    assert_equal households(:one), copy.household
    assert_equal catalog, copy.source_ingredient
    assert_equal @user, copy.created_by
    assert_equal [ "Chocolate chips", "fat", 3.49, 24 ], [ copy.ingredient, copy.family, copy.unit_price, copy.unit_servings ]
    assert_equal [ 1.0, "tbsp", 70 ], [ copy.nutrition_fact.serving_size, copy.nutrition_fact.serving_unit, copy.nutrition_fact.calories ]
    assert_match "Added Chocolate chips to your ingredients, with its cost and nutrition", response.body
    assert_no_changes -> { catalog.reload.attributes } do
      copy.update!(unit_price: 9.99)
    end
  end

  test "a catalog entry with gaps is copied and then filled in by the enrichment job" do
    Ingredient.create!(ingredient: "Honey", unit_price: 5.99, unit_servings: 20) # no family or nutrition

    assert_enqueued_with(job: IngredientEnrichmentJob) do
      add_line new_ingredient_name: "honey", quantity: 1
    end
    assert @recipe.recipe_ingredients.last.ingredient.source_ingredient.present?
  end

  test "the household's own ingredient still wins over the catalog's" do
    ours = households(:one).ingredients.create!(ingredient: "Chocolate chips")
    Ingredient.create!(ingredient: "Chocolate chips", unit_price: 3.49)

    assert_no_difference("Ingredient.count") do
      add_line new_ingredient_name: "chocolate chips", quantity: 1
    end
    assert_equal ours, @recipe.recipe_ingredients.last.ingredient
  end

  test "with several brands in the catalog, the unbranded one is copied" do
    Ingredient.create!(ingredient: "Chocolate chips", brand: "Nestle", unit_price: 4.49)
    generic = Ingredient.create!(ingredient: "Chocolate chips", unit_price: 3.49)

    add_line new_ingredient_name: "chocolate chips", quantity: 1
    assert_equal generic, @recipe.recipe_ingredients.last.ingredient.source_ingredient
  end

  test "typing the same catalog name again reuses the household's copy" do
    Ingredient.create!(ingredient: "Chocolate chips", unit_price: 3.49)
    add_line new_ingredient_name: "chocolate chips", quantity: 1

    assert_no_difference("Ingredient.count") do
      add_line new_ingredient_name: "Chocolate chips", quantity: 2
    end
    assert_equal 1, households(:one).ingredients.named("chocolate chips").count
  end

  test "a line that fails to save doesn't leave a catalog copy behind" do
    Ingredient.create!(ingredient: "Chocolate chips", unit_price: 3.49)
    # Make every line invalid for this one test.
    RecipeIngredient.define_method(:fail_for_test) { errors.add(:base, "nope") }
    RecipeIngredient.validate :fail_for_test

    assert_no_difference("Ingredient.count") do
      add_line new_ingredient_name: "chocolate chips", quantity: 1
    end
    assert_equal "Failed to add ingredient.", flash[:alert]
  ensure
    RecipeIngredient.skip_callback(:validate, :before, :fail_for_test)
    RecipeIngredient.remove_method(:fail_for_test)
  end

  test "limited members can't create ingredients this way" do
    sign_in users(:two)

    assert_no_difference("Ingredient.count") do
      add_line new_ingredient_name: "Chocolate chips", quantity: 1
    end
  end

  private

  def add_line(as: nil, **line)
    post recipe_recipe_ingredients_url(@recipe), params: { recipe_ingredient: line }, as:
  end
end
