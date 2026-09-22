require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  setup do
    @alice     = users(:one)   # owner of household one
    @bob       = users(:two)   # member of household one
    @carol     = users(:three) # owner of household two
    @household = households(:one)
  end

  test "for_household covers every member's recipes, whatever the visibility" do
    mine    = @alice.recipes.create!(title: "Mine",    visibility: "private")
    theirs  = @bob.recipes.create!(title: "Bobs",      visibility: "private")
    outside = @carol.recipes.create!(title: "Outside", visibility: "public")

    scoped = Recipe.for_household(@household)
    assert_includes scoped, mine
    assert_includes scoped, theirs
    refute_includes scoped, outside
  end

  test "public_beyond_household excludes the household's own and private recipes" do
    ours    = @alice.recipes.create!(title: "Ours",    visibility: "public")
    hidden  = @carol.recipes.create!(title: "Hidden",  visibility: "private")
    browsable = @carol.recipes.create!(title: "Shared", visibility: "public")

    scoped = Recipe.public_beyond_household(@household)
    refute_includes scoped, ours
    refute_includes scoped, hidden
    assert_includes scoped, browsable
  end

  test "browsable_by_household allows household recipes plus anything public" do
    sibling = @bob.recipes.create!(title: "Bobs private", visibility: "private")
    shared  = @carol.recipes.create!(title: "Shared",     visibility: "public")
    hidden  = @carol.recipes.create!(title: "Hidden",     visibility: "private")

    scoped = Recipe.browsable_by_household(@household)
    assert_includes scoped, sibling
    assert_includes scoped, shared
    refute_includes scoped, hidden
  end

  test "duplicate_for copies ingredients, steps and tags into the saving user" do
    source = @carol.recipes.create!(title: "Chili", description: "Warm", servings: 6, visibility: "public")
    source.recipe_ingredients.create!(ingredient: ingredients(:one), quantity: 2.0, unit: "cups")
    source.steps.create!(content: "Simmer gently")
    source.tags << @carol.tags.create!(tag: "Dinner", color: "#5f734c")

    copy = source.duplicate_for(@alice)

    assert_equal @alice, copy.user
    assert_equal source, copy.source_recipe
    assert_equal "Chili", copy.title
    assert_equal 6, copy.servings
    assert copy.private?, "a saved copy starts private"

    assert_equal [ingredients(:one).id], copy.recipe_ingredients.map(&:ingredient_id)
    assert_equal [2.0], copy.recipe_ingredients.map(&:quantity)
    assert_equal ["Simmer gently"], copy.steps.map { |s| s.content.to_plain_text }

    assert_equal ["Dinner"], copy.tags.map(&:tag)
    assert_equal [@alice.id], copy.tags.map(&:user_id), "tags are personal, so they're mirrored"
    refute_equal source.tags.map(&:id), copy.tags.map(&:id)
  end

  test "duplicate_for reuses a tag the saving user already has" do
    existing = @alice.tags.create!(tag: "Dinner", color: "#111111")
    source   = @carol.recipes.create!(title: "Chili", visibility: "public")
    source.tags << @carol.tags.create!(tag: "Dinner", color: "#5f734c")

    copy = source.duplicate_for(@alice)

    assert_equal [existing.id], copy.tags.map(&:id)
  end

  # ── Unit handling ─────────────────────────────────────────────────────────

  # 100 cal per 100 g, so grams in == calories out and the conversion is
  # readable straight off the assertion.
  def ingredient_at_100_cal_per_100g
    ing = Ingredient.create!(ingredient: "Test stuff", family: "protein")
    ing.create_nutrition_fact!(serving_size: 100, serving_unit: "g", calories: 100,
                               protein: 0, total_fat: 0, total_carb: 0)
    ing
  end

  def calories_for(quantity:, unit:)
    recipe = @alice.recipes.create!(title: "Unit probe", visibility: "private", servings: 1)
    recipe.recipe_ingredients.create!(ingredient: ingredient_at_100_cal_per_100g,
                                      quantity: quantity, unit: unit)
    recipe.total_calories
  end

  test "a blank unit counts as a whole piece rather than contributing nothing" do
    assert_equal 100, calories_for(quantity: 1, unit: nil)
    assert_equal 200, calories_for(quantity: 2, unit: "")
    assert_equal calories_for(quantity: 1, unit: "piece"), calories_for(quantity: 1, unit: nil)
  end

  test "every unit the picker offers converts to a weight" do
    RecipeIngredient::UNITS.each do |unit|
      assert calories_for(quantity: 1, unit: unit).positive?,
             "#{unit} should convert to a non-zero weight"
    end
  end

  test "the units added for the picker convert at the expected scale" do
    assert_in_delta 1000, calories_for(quantity: 1, unit: "liter"), 0.01
    assert_in_delta 473,  calories_for(quantity: 1, unit: "pint"),  0.01
    assert_in_delta 946,  calories_for(quantity: 1, unit: "quart"), 0.01
    assert_in_delta 30,   calories_for(quantity: 1, unit: "fl oz"), 0.01
  end

  test "a nil quantity still contributes nothing" do
    assert_equal 0, calories_for(quantity: nil, unit: "g")
  end

  test "the copy lands in the saving user's household" do
    source = @carol.recipes.create!(title: "Chili", visibility: "public")
    copy   = source.duplicate_for(@bob)

    assert_includes Recipe.for_household(@household), copy
    # The original stays in the browse pool — the index marks it "Saved"
    # rather than hiding it.
    assert_includes Recipe.public_beyond_household(@household), source
    assert source.owned_by_household?(households(:two))
    refute source.owned_by_household?(@household)
  end
end
