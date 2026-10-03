require "test_helper"

# Saving a public recipe that uses other recipes as ingredients brings those
# along, so the household isn't left pointing at someone else's sauce.
class SaveRecipeComponentsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)   # owner of household one
    @carol = users(:three) # owner of household two

    @chicken = @carol.recipes.create!(title: "Lemon Chicken", visibility: "public")
    @sauce   = @carol.recipes.create!(title: "Lemon Garlic Sauce", visibility: "public")
    @stock   = @carol.recipes.create!(title: "Chicken Stock", visibility: "private")
    @sauce.recipe_components.create!(component_recipe: @stock, multiplier: 0.5)
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 2)

    sign_in @alice
  end

  test "component recipes are copied into the household, all the way down" do
    assert_difference("Recipe.for_household(households(:one)).count", 3) do
      post save_to_household_recipe_url(@chicken)
    end

    chicken = Recipe.for_household(households(:one)).find_by!(source_recipe: @chicken)
    sauce   = Recipe.for_household(households(:one)).find_by!(source_recipe: @sauce)
    stock   = Recipe.for_household(households(:one)).find_by!(source_recipe: @stock)

    assert_equal [[sauce.id, 2.0]], chicken.recipe_components.map { |c| [c.component_recipe_id, c.multiplier.to_f] }
    assert_equal [[stock.id, 0.5]], sauce.recipe_components.map { |c| [c.component_recipe_id, c.multiplier.to_f] }
    assert [chicken, sauce, stock].all?(&:private?)
  end

  test "a component the household already saved is reused, not copied again" do
    post save_to_household_recipe_url(@sauce)
    saved_sauce = Recipe.order(:id).last(2).find { |r| r.source_recipe == @sauce }

    assert_difference("Recipe.count", 1) do
      post save_to_household_recipe_url(@chicken)
    end

    chicken = Recipe.order(:id).last
    assert_equal [saved_sauce.id], chicken.recipe_components.map(&:component_recipe_id)
  end

  test "a component the household owns stays as is" do
    own_sauce = @alice.recipes.create!(title: "Our Sauce")
    @chicken.recipe_components.destroy_all
    @chicken.recipe_components.create!(component_recipe: own_sauce, multiplier: 1)

    assert_difference("Recipe.count", 1) do
      post save_to_household_recipe_url(@chicken)
    end
    assert_equal [own_sauce.id], Recipe.order(:id).last.recipe_components.map(&:component_recipe_id)
  end

  test "a component used twice in the tree is copied once" do
    @chicken.recipe_components.create!(component_recipe: @stock, multiplier: 1)

    assert_difference("Recipe.count", 3) do
      post save_to_household_recipe_url(@chicken)
    end
  end
end
