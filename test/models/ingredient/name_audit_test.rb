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
    oil       = ingredient("Vegetable oil", family: "oil")
    duplicate = ingredient("Vegetable or canola oil", unit_price: 3.5)
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
    assert_equal "oil", oil.family                 # the kept one's own value wins
    rows = GroceryList.where(household: @household, week_of: week)
    assert_equal [ [ oil.id, 3 ] ], rows.pluck(:ingredient_id, :units) # combined, not listed twice
  end

  test "near-identical names in one household merge, keeping the most used" do
    hyphen = ingredient("All-purpose flour")
    space  = ingredient("All purpose flour")
    2.times { @recipe.recipe_ingredients.create!(ingredient: space, quantity: 1, unit: "cup") }

    change = Ingredient::NameAudit.new(household: @household).changes.sole

    assert change.merge?
    assert_equal hyphen, change.ingredient
    assert_equal space, change.into
  end

  test "never merges across households or across brands" do
    ingredient("Vegetable or canola oil")
    households(:one).ingredients.create!(ingredient: "Vegetable oil")
    ingredient("Butter", brand: "Kerrygold")
    ingredient("Butter", brand: "Land O Lakes")

    kinds = Ingredient::NameAudit.new(household: @household).changes.map(&:kind)

    assert_equal [ :rename ], kinds
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
