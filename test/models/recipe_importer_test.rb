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
    @olive_oil = Ingredient.create!(ingredient: "Olive oil", family: "fat")
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
end
