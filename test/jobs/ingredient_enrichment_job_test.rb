require "test_helper"
require "minitest/mock"
require_relative "../support/fake_ollama_assistant"

class IngredientEnrichmentJobTest < ActiveSupport::TestCase
  setup do
    @ingredient = Ingredient.create!(ingredient: "Smoked paprika", created_by: users(:one))
  end

  def enrich(ai = FakeOllamaAssistant.new)
    OllamaAssistant.stub(:new, ai) { IngredientEnrichmentJob.perform_now(@ingredient.id) }
    @ingredient.reload
  end

  test "it fills in family, pricing and nutrition" do
    enrich

    assert_equal "produce", @ingredient.family
    assert_equal 1.5, @ingredient.unit_price
    assert_equal 4, @ingredient.unit_servings

    facts = @ingredient.nutrition_fact
    assert_equal 10, facts.calories
    assert_equal 1, facts.protein
    assert_equal 1, facts.serving_size
    assert_equal "cup", facts.serving_unit
  end

  test "it copes with the AI's string-keyed JSON as well as the offline fallback" do
    string_keyed = Class.new(FakeOllamaAssistant) do
      def estimate_nutrition_facts(_ingredients)
        [{ "calories" => 42, "protein" => 3.0, "total_fat" => 1.0, "total_carb" => 5.0,
           "serving_size" => 100, "serving_unit" => "g",
           "unit_price" => 2.25, "unit_servings" => 8 }]
      end
    end

    enrich(string_keyed.new)

    assert_equal 2.25, @ingredient.unit_price
    assert_equal 8, @ingredient.unit_servings
    assert_equal 42, @ingredient.nutrition_fact.calories
    assert_equal "g", @ingredient.nutrition_fact.serving_unit
  end

  test "it never overwrites what the user already entered" do
    @ingredient.update!(family: "spices", unit_price: 9.99, unit_servings: 50)
    @ingredient.create_nutrition_fact!(calories: 5, serving_size: 1, serving_unit: "tsp")

    enrich

    assert_equal "spices", @ingredient.family
    assert_equal 9.99, @ingredient.unit_price
    assert_equal 50, @ingredient.unit_servings
    assert_equal 5, @ingredient.nutrition_fact.calories
  end

  test "a deleted ingredient is a no-op rather than an error" do
    id = @ingredient.id
    @ingredient.destroy!

    assert_nothing_raised do
      OllamaAssistant.stub(:new, FakeOllamaAssistant.new) { IngredientEnrichmentJob.perform_now(id) }
    end
  end

  test "recipes using the ingredient get the corrected row and macros pushed to them" do
    recipe = users(:one).recipes.create!(title: "Rub", visibility: "private", servings: 2)
    line   = recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 2, unit: "tsp")

    assert_equal 0, recipe.total_calories, "no nutrition facts yet"

    broadcasts = []
    recorder = ->(stream, **options) { broadcasts << [stream, options[:target]] }

    Turbo::StreamsChannel.stub(:broadcast_replace_to, recorder) { enrich }

    assert_equal [[recipe, "recipe_ingredient_#{line.id}"], [recipe, "macros_chart"]], broadcasts
    assert recipe.reload.total_calories.positive?, "the estimate now feeds the chart"
  end

  test "the row partial renders outside a request, the way the broadcast does" do
    recipe = users(:one).recipes.create!(title: "Rub", visibility: "private", servings: 2)
    line   = recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 2, unit: "tsp")

    html = ApplicationController.render(
      partial: "recipes/recipe_ingredient_row",
      locals:  { recipe_ingredient: line, recipe: recipe }
    )

    assert_includes html, "recipe_ingredient_#{line.id}"
    assert_includes html, "/recipes/#{recipe.id}/recipe_ingredients/#{line.id}"
  end
end
