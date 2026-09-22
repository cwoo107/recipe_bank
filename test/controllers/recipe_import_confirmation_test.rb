require "test_helper"
require "minitest/mock"
require_relative "../support/fake_ollama_assistant"

# The user-facing half of the confirmation gate: the paused import renders a
# form, and submitting it resumes the import with the user's decisions.
class RecipeImportConfirmationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @olive_oil = Ingredient.create!(ingredient: "Olive oil", family: "fat")
    @job = @user.recipe_import_jobs.create!(
      url: "https://example.com/r",
      status: :awaiting_confirmation,
      current_step: "Confirm ingredient matches",
      progress: 2,
      total_steps: 5,
      scraped_data: {
        "title" => "Test Bake", "description" => "A test", "servings" => 4,
        "ingredients" => ["2 tablespoons olive oil", "1 cup zzqqx flour"],
        "steps" => ["Mix it", "Bake it"]
      },
      matched_ingredients: [
        { "parsed" => { "original" => "2 tablespoons olive oil", "name" => "olive oil",
                        "search_name" => "olive oil", "quantity" => 2.0, "unit" => "tablespoons" },
          "match_id" => @olive_oil.id, "match_name" => "Olive oil",
          "confidence" => 1.0, "method" => "exact" },
        { "parsed" => { "original" => "1 cup zzqqx flour", "name" => "zzqqx flour",
                        "search_name" => "zzqqx flour", "quantity" => 1.0, "unit" => "cup" },
          "match_id" => nil, "match_name" => nil,
          "confidence" => 0.0, "method" => "none" }
      ]
    )

    # Run the resume inline so the test isn't racing a background thread.
    RecipeImportsController.background_runner = RecipeImportsController::INLINE_RUNNER
    sign_in @user
  end

  teardown do
    RecipeImportsController.background_runner = RecipeImportsController::THREADED_RUNNER
  end

  def confirm(indexes)
    OllamaAssistant.stub(:new, FakeOllamaAssistant.new) do
      post confirm_ingredients_recipe_import_url(@job), params: { confirmed: indexes }
    end
    @job.reload
  end

  test "a paused import shows each ingredient beside its match" do
    get recipe_import_url(@job)

    assert_response :success
    assert_match "Confirm ingredient matches", response.body
    assert_match "2 tablespoons olive oil", response.body
    assert_match "Olive oil", response.body
    assert_match "1 cup zzqqx flour", response.body
    assert_match "No match found", response.body
    # The matched row is tickable and pre-ticked; the unmatched one isn't.
    assert_match 'id="confirmed_0"', response.body
    assert_match(/id="confirmed_0".*checked="checked"/, response.body)
    assert_no_match 'id="confirmed_1"', response.body
  end

  test "a paused import does not auto-refresh away the user's ticks" do
    get recipe_import_url(@job)
    assert_no_match "http-equiv=\"refresh\"", response.body
  end

  test "confirming a match reuses that ingredient and creates the rest" do
    assert_difference("Ingredient.count", 1) do
      confirm(["0"])
    end

    assert @job.completed?
    used = @job.recipe.recipe_ingredients.includes(:ingredient).map(&:ingredient)
    assert_includes used, @olive_oil
    assert_equal ["Olive oil", "Zzqqx flour"], used.map(&:ingredient).sort
  end

  test "confirming nothing creates a new ingredient for every line" do
    assert_difference("Ingredient.count", 2) do
      confirm([])
    end

    used = @job.recipe.recipe_ingredients.includes(:ingredient).map(&:ingredient)
    refute_includes used, @olive_oil
  end

  test "a blank confirmed value doesn't sneak through as row zero" do
    assert_difference("Ingredient.count", 2) do
      OllamaAssistant.stub(:new, FakeOllamaAssistant.new) do
        post confirm_ingredients_recipe_import_url(@job), params: { confirmed: [""] }
      end
    end

    used = @job.reload.recipe.recipe_ingredients.includes(:ingredient).map(&:ingredient)
    refute_includes used, @olive_oil
  end

  test "an import that isn't paused can't be confirmed" do
    @job.update!(status: :creating_recipe)

    assert_no_difference("Recipe.count") do
      post confirm_ingredients_recipe_import_url(@job), params: { confirmed: ["0"] }
    end
    assert_redirected_to recipe_import_url(@job)
  end

  test "another user's import can't be confirmed" do
    sign_in users(:three)

    post confirm_ingredients_recipe_import_url(@job), params: { confirmed: ["0"] }
    assert_response :not_found
    assert @job.reload.awaiting_confirmation?
  end
end
