require "test_helper"

class Ingredient::NameAuditTest < ActiveSupport::TestCase
  setup do
    @household = households(:two) # no fixture ingredients, so only what each test adds
    @user      = users(:three)    # carol, household :two
    @recipe    = Recipe.create!(title: "Pasta", servings: 2, user: @user)
  end

  def ingredient(name, **attributes)
    @household.ingredients.create!(ingredient: name, **attributes)
  end

  test "plans a rename for a mangled name without saving anything" do
    parmesan = ingredient(". finely parmesan")

    changes = Ingredient::NameAudit.new(household: @household).changes

    assert_equal [ [ :rename, parmesan, "Parmesan" ] ], changes.map { |c| [ c.kind, c.ingredient, c.to_name ] }
    assert_equal ". finely parmesan", parmesan.reload.ingredient
  end

  test "apply! renames" do
    parmesan = ingredient(". finely parmesan")

    Ingredient::NameAudit.new(household: @household).apply!

    assert_equal "Parmesan", parmesan.reload.ingredient
  end

  test "apply! merges an ingredient that turns out to be a duplicate once cleaned" do
    oil       = ingredient("Parmesan", family: "dairy")
    duplicate = ingredient(". finely parmesan", unit_price: 3.5) # a confident cleanup — no notes
    line      = @recipe.recipe_ingredients.create!(ingredient: duplicate, quantity: 2, unit: "tbsp")
    tag       = Tag.create!(tag: "Pantry", color: "olive", user: @user)
    duplicate.tags << tag
    duplicate.create_nutrition_fact!(calories: 120)
    week = Date.current.beginning_of_week
    GroceryList.create!(ingredient: oil, household: @household, user: @user, week_of: week, units: 1)
    GroceryList.create!(ingredient: duplicate, household: @household, user: @user, week_of: week, units: 2)

    change = Ingredient::NameAudit.new(household: @household).changes.sole
    assert change.merge?
    assert_equal oil, change.into

    Ingredient::NameAudit.new(household: @household).apply!

    assert_nil Ingredient.find_by(id: duplicate.id)
    assert_equal oil, line.reload.ingredient
    assert_includes oil.reload.tags, tag
    assert_equal 120, oil.nutrition_fact.calories
    assert_equal 3.5, oil.unit_price               # filled in from the duplicate
    assert_equal "dairy", oil.family               # the kept one's own value wins
    rows = GroceryList.where(household: @household, week_of: week)
    assert_equal [ [ oil.id, 3 ] ], rows.pluck(:ingredient_id, :units) # combined, not listed twice
  end

  test "names that only look alike are flagged, not merged — the app treats them as different ingredients" do
    hyphen = ingredient("All-purpose flour")
    space  = ingredient("All purpose flour")
    2.times { @recipe.recipe_ingredients.create!(ingredient: space, quantity: 1, unit: "cup") }

    change = Ingredient::NameAudit.new(household: @household).changes.sole

    assert_equal :review, change.kind
    assert_equal hyphen, change.ingredient
    assert_match(/looks like the same thing as ##{space.id}/, change.notes.join)

    Ingredient::NameAudit.new(household: @household).apply!
    assert hyphen.reload.persisted?
  end

  test "a guessed cleanup never merges into another ingredient" do
    oil   = ingredient("Vegetable oil")
    guess = ingredient("Vegetable or canola oil") # "kept the first" alternative — a judgement call

    change = Ingredient::NameAudit.new(household: @household).changes.sole

    assert_equal :review, change.kind
    assert_equal guess, change.ingredient
    assert_match(/would become a duplicate of ##{oil.id}/, change.notes.join)
    assert_match(/kept the first/, change.notes.join)

    Ingredient::NameAudit.new(household: @household).apply!
    assert_equal "Vegetable or canola oil", guess.reload.ingredient
  end

  test "each household's own copy of an ingredient is left alone" do
    mine   = ingredient("Vegetable oil")
    theirs = households(:one).ingredients.create!(ingredient: "Vegetable oil")
    ingredient("Butter", brand: "Kerrygold")
    ingredient("Butter", brand: "Land O Lakes")

    assert_empty Ingredient::NameAudit.new.changes.select { |change| [ mine, theirs ].include?(change.ingredient) }
    assert_empty Ingredient::NameAudit.new(household: @household).changes
  end

  test "the shared catalog is never touched" do
    catalog = Ingredient.create!(ingredient: ". finely parmesan", household: nil)

    assert_not_includes Ingredient::NameAudit.new.changes.map(&:ingredient), catalog
  end

  test "a merge keeps the copy link, so copying the original again reuses the kept ingredient" do
    original  = households(:one).ingredients.create!(ingredient: "Parmesan")
    keeper    = ingredient("Parmesan")
    duplicate = ingredient(". finely parmesan", source_ingredient: original)

    Ingredient::NameAudit.new(household: @household).apply!

    assert_nil Ingredient.find_by(id: duplicate.id)
    assert_equal original, keeper.reload.source_ingredient
    assert_no_difference("Ingredient.count") do
      assert_equal keeper, original.copy_for(@household, user: @user)
    end
  end

  test "other households' copies of a merged-away ingredient trace back to the kept one" do
    keeper    = ingredient("Parmesan")
    duplicate = ingredient(". finely parmesan")
    their_copy = households(:one).ingredients.create!(ingredient: "Parmesan", source_ingredient: duplicate)

    Ingredient::NameAudit.new(household: @household).apply!

    assert_equal keeper, their_copy.reload.source_ingredient
  end

  test "two copies of different originals aren't merged, since only one copy link could survive" do
    first_original  = households(:one).ingredients.create!(ingredient: "Parmesan")
    second_original = households(:one).ingredients.create!(ingredient: "Parmesan", brand: "Other")
    keeper    = ingredient("Parmesan", source_ingredient: first_original)
    duplicate = ingredient(". finely parmesan", source_ingredient: second_original)

    change = Ingredient::NameAudit.new(household: @household).changes.sole

    assert_equal :review, change.kind
    assert_equal duplicate, change.ingredient
    assert_match(/copy of a different original/, change.notes.join)
    assert keeper.persisted?
  end

  test "flags a clean-looking name that still needs a person" do
    ingredient("Salt and pepper")

    change = Ingredient::NameAudit.new(household: @household).changes.sole

    assert_equal :review, change.kind
    assert_match(/two ingredients/, change.notes.join)
  end

  test "the rake task is a dry run unless APPLY=1" do
    parmesan = ingredient(". finely parmesan")
    # Just this rake file, in a fresh Rake application — Rails' load_tasks
    # only runs once per process, which isn't reliable under parallel tests.
    require "rake"
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/ingredients.rake")

    with_env("HOUSEHOLD" => @household.id.to_s) do
      assert_output(/Dry run.*"Parmesan"/m) { Rake::Task["ingredients:normalize_names"].execute }
    end
    assert_equal ". finely parmesan", parmesan.reload.ingredient

    with_env("HOUSEHOLD" => @household.id.to_s, "APPLY" => "1") do
      assert_output(/Applying/) { Rake::Task["ingredients:normalize_names"].execute }
    end
    assert_equal "Parmesan", parmesan.reload.ingredient
  end

  private

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
