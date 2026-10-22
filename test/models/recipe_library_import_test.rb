require "test_helper"

class RecipeLibraryImportTest < ActiveSupport::TestCase
  setup do
    rice = Ingredient.create!(ingredient: "Basmati rice", family: "grain", unit_price: 4.99, unit_servings: 20)
    rice.create_nutrition_fact!(serving_size: 0.25, serving_unit: "cup", calories: 160, protein: 3, total_fat: 0, total_carb: 36)
    Ingredient.create!(ingredient: "Butter unsalted", family: "dairy")

    @file = Tempfile.new([ "library", ".json" ])
    write(
      { "title" => "Buttered Rice", "description" => "Simple and quick.", "servings" => 4,
        "tags" => [ "Dinner", "Quick & Easy", "Not a real tag" ],
        "ingredients" => [ { "name" => "Basmati rice", "quantity" => 1, "unit" => "cup", "optional" => false },
                           { "name" => "butter unsalted", "quantity" => 2, "unit" => "tbsp", "optional" => true } ],
        "steps" => [ "Rinse the rice.", "Simmer for 15 minutes.", "Stir in the butter." ] },
      { "title" => "Mystery Stew", "servings" => 4,
        "ingredients" => [ { "name" => "Unicorn meat", "quantity" => 1, "unit" => "lb" },
                           { "name" => "Basmati rice", "quantity" => 1, "unit" => "handful" } ],
        "steps" => [ "Stew it." ] }
    )
  end

  teardown { @file.close! }

  def write(*recipes)
    @file.rewind
    @file.truncate(0)
    @file.write({ "recipes" => recipes }.to_json)
    @file.flush
  end

  def import = Recipe::LibraryImport.new(@file.path)

  test "a dry run says what would happen, and flags what can't be imported" do
    rows = import.rows

    assert_equal [ :create, :invalid ], rows.map(&:action)
    problems = rows.last.problems.join(" ")
    assert_match "not in the ingredient catalog: Unicorn meat", problems
    assert_match "units the picker doesn't offer: handful", problems
    assert_nil import.library_user, "nothing is created on a dry run"
  end

  test "applying creates the library account and its public recipes from the catalog" do
    assert_equal 1, import.apply!

    user = User.find_by!(email: Recipe::LibraryImport::LIBRARY_EMAIL)
    assert_equal "HomemakersHaven Kitchen", user.household.family_name
    assert_equal "HomemakersHaven Kitchen", user.household.household_members.find_by!(user:).name

    recipe = user.recipes.find_by!(title: "Buttered Rice")
    assert recipe.public?
    assert_equal 4, recipe.servings
    assert_equal [ "Rinse the rice.", "Simmer for 15 minutes.", "Stir in the butter." ],
                 recipe.instruction_items.map { |step| step.content.to_plain_text }
    assert_equal [ "Dinner", "Quick & Easy" ], recipe.tags.map(&:tag).sort

    # Ingredients are the library household's own copies of the catalog's.
    rice = recipe.recipe_ingredients.joins(:ingredient).find_by!(ingredients: { ingredient: "Basmati rice" })
    assert_equal user.household, rice.ingredient.household
    assert_equal 160, rice.ingredient.nutrition_fact.calories
    assert recipe.recipe_ingredients.find_by!(unit: "tbsp").optional?

    assert_includes Recipe.public_beyond_household(households(:one)), recipe
  end

  test "re-running leaves recipes already in the library alone" do
    import.apply!

    rerun = import
    assert_equal :unchanged, rerun.rows.first.action
    assert_no_difference("Recipe.count") { rerun.apply! }
    assert_equal 1, User.where(email: Recipe::LibraryImport::LIBRARY_EMAIL).count
  end

  test "an edited recipe is flagged, and REFRESH rewrites the library's copy in place" do
    import.apply!
    recipe = User.find_by!(email: Recipe::LibraryImport::LIBRARY_EMAIL).recipes.find_by!(title: "Buttered Rice")
    saved  = recipe.duplicate_for(users(:one)) # a household's own copy

    edited = JSON.parse(File.read(@file.path))["recipes"]
    edited.first["servings"] = 6
    edited.first["ingredients"].first["quantity"] = 1.5
    edited.first["steps"] << "Fluff with a fork."
    write(*edited)

    plain = import.rows.first
    assert_equal :unchanged, plain.action, "without REFRESH nothing is overwritten"
    assert_equal [ "servings 4 → 6", "ingredients", "steps" ], plain.changes

    refresh = Recipe::LibraryImport.new(@file.path, refresh: true)
    assert_equal :update, refresh.rows.first.action
    assert_equal 1, refresh.apply!

    recipe.reload
    assert_equal 6, recipe.servings
    assert_equal 1.5, recipe.recipe_ingredients.joins(:ingredient).find_by!(ingredients: { ingredient: "Basmati rice" }).quantity
    assert_equal "Fluff with a fork.", recipe.instruction_items.last.content.to_plain_text
    assert_equal [ "Dinner", "Quick & Easy" ], recipe.tags.map(&:tag).sort

    assert_equal 4, saved.reload.servings, "a household's saved copy is left alone"
    assert_equal :unchanged, Recipe::LibraryImport.new(@file.path, refresh: true).rows.first.action
  end

  test "the recipe library file is valid against the catalog" do
    path = Rails.root.join("db/recipe_library.json")
    skip "no recipe library file yet" unless path.exist?

    # Load the real catalog, then check every recipe would import.
    Ingredient::CatalogImport.new(Rails.root.join("db/ingredients.csv").to_s).apply!
    invalid = Recipe::LibraryImport.new(path.to_s).rows.select(&:invalid?)

    assert_empty invalid.map { |row| "#{row.title}: #{row.problems.join('; ')}" }
  end
end
