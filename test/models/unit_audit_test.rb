require "test_helper"

class UnitAuditTest < ActiveSupport::TestCase
  setup do
    @recipe = users(:one).recipes.create!(title: "Pancakes")
    @flour  = households(:one).ingredients.create!(ingredient: "Flour")
  end

  # Written straight to the column, like data saved before units were tidied.
  def line(unit, recipe: @recipe, ingredient: @flour)
    recipe.recipe_ingredients.create!(ingredient:, quantity: 2).tap { |line| line.update_column(:unit, unit) }
  end

  def fact(unit, ingredient)
    ingredient.create_nutrition_fact!(serving_size: 1, calories: 100).tap { |fact| fact.update_column(:serving_unit, unit) }
  end

  test "plans one change per distinct spelling, with how many rows use it" do
    2.times { line("Tablespoons") }
    line("tbsp")
    line("whole")
    line("can")
    fact("Cups", @flour)

    changes = UnitAudit.new.changes.index_by { |change| [ change.source.label, change.from ] }

    assert_equal [ :update, "tbsp", 2 ], changes[[ "recipe lines", "Tablespoons" ]].to_h.values_at(:kind, :to, :count)
    assert_equal [ :update, nil, 1 ],    changes[[ "recipe lines", "whole" ]].to_h.values_at(:kind, :to, :count)
    assert_equal :review,                changes[[ "recipe lines", "can" ]].kind
    assert_equal [ :update, "cup" ],     changes[[ "nutrition facts", "Cups" ]].to_h.values_at(:kind, :to)
    assert_nil changes[[ "recipe lines", "tbsp" ]], "already clean"
  end

  test "apply rewrites the units and never the amounts" do
    a = line("Tablespoons")
    b = line("can")
    f = fact("Grams", @flour)

    UnitAudit.new.apply!

    assert_equal [ "tbsp", 2.0 ], [ a.reload.unit, a.quantity ]
    assert_equal "can", b.reload.unit
    assert_equal "g", f.reload.serving_unit
    assert_empty UnitAudit.new.changes.select(&:update?)
  end

  test "a household scope leaves other households alone" do
    theirs_recipe = users(:three).recipes.create!(title: "Theirs")
    theirs = line("Tablespoons", recipe: theirs_recipe, ingredient: households(:two).ingredients.create!(ingredient: "Salt"))
    ours = line("Tablespoons")

    UnitAudit.new(household: households(:one)).apply!

    assert_equal "tbsp", ours.reload.unit
    assert_equal "Tablespoons", theirs.reload.unit
  end

  test "the shared catalog's nutrition facts are left alone" do
    catalog = Ingredient.create!(ingredient: "Catalog flour")
    catalog_fact = fact("Cups", catalog)

    UnitAudit.new.apply!

    assert_equal "Cups", catalog_fact.reload.serving_unit
  end
end
