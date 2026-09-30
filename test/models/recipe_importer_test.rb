require "test_helper"
require "minitest/mock"
require_relative "../support/fake_ollama_assistant"

# The import pauses after matching so the user can vet each match; these cover
# the pause, what gets persisted across it, and how the resume honours the
# user's ticks.
class RecipeImporterTest < ActiveSupport::TestCase
  FakeScraper = Struct.new(:data) { def scrape = data }

  SCRAPED = {
    title: "Test Bake",
    description: "A test",
    servings: 4,
    ingredients: ["2 tablespoons olive oil", "1 cup zzqqx flour"],
    steps: ["Mix it", "Bake it"]
  }.freeze

  setup do
    @user = users(:one)
    @olive_oil = Ingredient.create!(household: households(:one), ingredient: "Olive oil", family: "fat")
    @job = @user.recipe_import_jobs.create!(url: "https://example.com/r", status: :pending,
                                            progress: 0, total_steps: 5)
  end

  def run_match_phase
    OllamaAssistant.stub(:new, FakeOllamaAssistant.new) do
      RecipeScraper.stub(:new, FakeScraper.new(SCRAPED)) do
        RecipeImporter.new(@job).perform
      end
    end
    @job.reload
  end

  def run_resume
    OllamaAssistant.stub(:new, FakeOllamaAssistant.new) do
      RecipeImporter.new(@job).resume_after_confirmation
    end
    @job.reload
  end

  test "the import stops at the confirmation gate instead of creating the recipe" do
    run_match_phase

    assert @job.awaiting_confirmation?
    assert_equal "Confirm ingredient matches", @job.current_step
    assert_nil @job.recipe_id
    assert_equal 0, Recipe.where(title: "Test Bake").count
  end

  test "the paused job carries the matches the user needs to see" do
    run_match_phase

    matches = @job.ingredient_matches
    assert_equal 2, matches.length

    oil = matches.first
    assert_equal "2 tablespoons olive oil", oil.original
    assert_equal @olive_oil.id, oil.match_id
    assert_equal "Olive oil", oil.match_name
    assert oil.matched?

    flour = matches.last
    refute flour.matched?
    assert flour.creates_new_ingredient?
  end

  test "matches survive the JSON round trip as real ingredient records" do
    run_match_phase

    rehydrated = RecipeImporter.deserialize_results(@job.reload.matched_ingredients)
    assert_equal [@olive_oil, nil], rehydrated.map { |r| r[:match] }
    assert_equal "olive oil", rehydrated.first[:parsed][:name]
  end

  test "a confirmed match is reused and everything else becomes a new ingredient" do
    run_match_phase
    @job.apply_ingredient_confirmations!(["0"])

    assert_difference("Ingredient.count", 1) do
      run_resume
    end

    assert @job.completed?
    recipe = @job.recipe
    assert_equal "Test Bake", recipe.title
    assert_equal 2, recipe.steps.count

    used = recipe.recipe_ingredients.includes(:ingredient).map { |ri| ri.ingredient }
    assert_includes used, @olive_oil
    assert_equal ["Zzqqx flour"], (used - [@olive_oil]).map(&:ingredient)
  end

  test "an unticked match is discarded and a new ingredient is created in its place" do
    run_match_phase
    @job.apply_ingredient_confirmations!([]) # user ticked nothing

    assert_difference("Ingredient.count", 2) do
      run_resume
    end

    used = @job.recipe.recipe_ingredients.includes(:ingredient).map(&:ingredient)
    refute_includes used, @olive_oil, "the rejected match must not be reused"
    assert_equal ["Olive oil", "Zzqqx flour"], used.map(&:ingredient).sort
    assert used.all? { |i| i.created_by == @user }
  end

  test "unticking clears the stored match so the UI stops showing it" do
    run_match_phase
    @job.apply_ingredient_confirmations!([])

    oil = @job.ingredient_matches.first
    refute oil.matched?
    assert_equal false, oil.confirmed
    assert_equal 0, @job.matched_ingredient_count
    assert_equal 2, @job.new_ingredient_count
  end

  test "an index the user never saw cannot resurrect a match" do
    run_match_phase
    @job.apply_ingredient_confirmations!(["1"]) # the unmatched row

    flour = @job.ingredient_matches.last
    refute flour.matched?, "confirming a row with no match must not invent one"
  end

  test "resume records a failure on the job rather than leaving it hanging" do
    run_match_phase
    @job.update!(scraped_data: nil)

    assert_raises(NoMethodError) do
      OllamaAssistant.stub(:new, FakeOllamaAssistant.new) { RecipeImporter.new(@job).resume_after_confirmation }
    end

    assert @job.reload.failed?
    assert @job.error_message.present?
  end

  test "a match from another household is copied in rather than linked to" do
    @olive_oil.update!(household: households(:two))
    run_match_phase
    assert_equal @olive_oil.id, @job.ingredient_matches.first.match_id, "falls back to anyone's ingredients"

    @job.apply_ingredient_confirmations!(["0"])
    run_resume

    oil = @job.recipe.ingredients.find_by(ingredient: "Olive oil")
    refute_equal @olive_oil, oil
    assert_equal households(:one), oil.household
    assert_equal @olive_oil, oil.source_ingredient
  end

  test "the household's own ingredient wins over another household's" do
    @olive_oil.update!(household: households(:two))
    ours = households(:one).ingredients.create!(ingredient: "Olive oil", family: "fat")

    run_match_phase

    assert_equal ours.id, @job.ingredient_matches.first.match_id
  end

  test "new ingredients from an import belong to the importer's household" do
    run_match_phase
    @job.apply_ingredient_confirmations!(["0"])
    run_resume

    flour = @job.recipe.ingredients.find_by(ingredient: "Zzqqx flour")
    assert_equal households(:one), flour.household
  end

  # ── Saved recipes are never reported as failed imports ──

  test "a progress broadcast that fails doesn't fail the import" do
    run_match_phase
    @job.update!(status: :resolving_with_ai)
    @job.define_singleton_method(:broadcast_replace_to) do |*|
      raise Redis::CannotConnectError, "Error connecting to Redis"
    end

    run_resume

    assert @job.completed?
    assert_nil @job.error_message
    assert_equal 1, Recipe.where(title: "Test Bake").count
  end

  test "an error after the recipe is committed still records the import as completed" do
    run_match_phase
    @job.update!(status: :resolving_with_ai)
    failed_once = false
    @job.define_singleton_method(:update!) do |attributes|
      if attributes[:status] == :completed && !failed_once
        failed_once = true
        raise ActiveRecord::StatementInvalid, "connection lost"
      end
      super(attributes)
    end

    recipe = OllamaAssistant.stub(:new, FakeOllamaAssistant.new) { RecipeImporter.new(@job).resume_after_confirmation }

    @job.reload
    assert @job.completed?
    assert_equal recipe.id, @job.recipe_id
    assert_equal 1, Recipe.where(title: "Test Bake").count
  end

  test "resuming an import that already saved its recipe doesn't save it again" do
    run_match_phase
    run_resume
    first = @job.recipe

    assert_equal first, OllamaAssistant.stub(:new, FakeOllamaAssistant.new) { RecipeImporter.new(@job).resume_after_confirmation }
    assert_equal 1, Recipe.where(title: "Test Bake").count
  end

  # ── Nutrition estimates ──

  # What the real Ollama client returns: parsed JSON (string keys), and the
  # model is free to recapitalise the name.
  class JsonOllamaAssistant < FakeOllamaAssistant
    def estimate_nutrition_facts(ingredients)
      ingredients.map do |i|
        { "name" => i[:name].to_s.titleize, "calories" => 364, "protein" => 10.0, "total_fat" => 1.0,
          "total_carb" => 76.0, "serving_size" => 100, "serving_unit" => "g", "unit_price" => 4.25, "unit_servings" => 20 }
      end
    end
  end

  test "an AI nutrition estimate (string keys) is saved on the new ingredient" do
    run_match_phase
    OllamaAssistant.stub(:new, JsonOllamaAssistant.new) { RecipeImporter.new(@job).resume_after_confirmation }

    flour = @job.reload.recipe.ingredients.find_by(ingredient: "Zzqqx flour")
    assert_equal 364, flour.nutrition_fact.calories
    assert_equal "g", flour.nutrition_fact.serving_unit
    assert_equal 4.25, flour.unit_price
    assert_equal 20, flour.unit_servings
  end

  test "the offline fallback estimate (symbol keys) is still saved" do
    run_match_phase
    run_resume

    flour = @job.recipe.ingredients.find_by(ingredient: "Zzqqx flour")
    assert_equal 10, flour.nutrition_fact.calories
    assert_equal 1.5, flour.unit_price
  end
end
