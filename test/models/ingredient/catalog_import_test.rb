require "test_helper"

class Ingredient::CatalogImportTest < ActiveSupport::TestCase
  HEADER = "ingredient,brand,family,organic,unit_price,unit_servings,serving_size,serving_unit,calories,protein,total_fat,total_carb".freeze

  def import(*lines)
    file = Tempfile.new([ "catalog", ".csv" ])
    file.write(([ HEADER ] + lines).join("\n"))
    file.close
    @files = (@files || []) << file
    Ingredient::CatalogImport.new(file.path)
  end

  teardown { @files&.each(&:unlink) }

  def catalog = Ingredient.where(household_id: nil)

  test "creates catalog ingredients with their nutrition facts" do
    rows = import("Chocolate chips,,fat,false,3.49,24,1,Tablespoons,70,1,4,9").tap(&:apply!).rows

    assert_equal [ :create ], rows.map(&:action)
    chips = catalog.find_by!(ingredient: "Chocolate chips")
    assert_nil chips.household_id
    assert_equal [ "fat", false, 3.49, 24 ], [ chips.family, chips.organic, chips.unit_price, chips.unit_servings ]
    fact = chips.nutrition_fact
    assert_equal [ 1.0, "tbsp", 70, 1.0, 4.0, 9.0 ],
                 [ fact.serving_size, fact.serving_unit, fact.calories, fact.protein, fact.total_fat, fact.total_carb ]
  end

  test "blank family, unit and nutrition are fine" do
    import("Honey,,,false,5.99,20,1,tbsp,60,0,0,17", "Eggs large,,protein,false,3.99,12,1,,70,6,5,0", "Water,,,,,,,,,,,").apply!

    assert_nil catalog.find_by!(ingredient: "Honey").family
    assert_nil catalog.find_by!(ingredient: "Eggs large").nutrition_fact.serving_unit, "a count, like '1 egg'"
    assert_nil catalog.find_by!(ingredient: "Water").nutrition_fact
  end

  test "re-running the same file changes nothing" do
    line = "Chocolate chips,,fat,false,3.49,24,1,tbsp,70,1,4,9"
    import(line).apply!

    assert_no_difference([ "Ingredient.count", "NutritionFact.count" ]) do
      assert_equal [ :unchanged ], import(line).tap(&:apply!).rows.map(&:action)
    end
  end

  test "edited values update the catalog entry, matched by name ignoring case" do
    import("Chocolate chips,,fat,false,3.49,24,1,tbsp,70,1,4,9").apply!

    rows = import("CHOCOLATE CHIPS,,fat,false,3.99,24,1,tbsp,80,1,4,9").tap(&:apply!).rows

    assert_equal :update, rows.first.action
    assert_equal({ "unit_price" => 3.99 }, rows.first.attributes)
    assert_equal({ "calories" => 80 }, rows.first.nutrition)
    chips = catalog.find_by!(ingredient: "Chocolate chips")
    assert_equal [ 3.99, 80 ], [ chips.unit_price, chips.nutrition_fact.calories ]
  end

  test "a blank cell never clears what's already there" do
    import("Chocolate chips,,fat,false,3.49,24,1,tbsp,70,1,4,9").apply!

    assert_equal [ :unchanged ], import("Chocolate chips,,,,,,,,,,,").rows.map(&:action)
  end

  test "the same name with another brand is a different ingredient" do
    import("Chocolate chips,,fat,false,3.49,24,1,tbsp,70,1,4,9", "Chocolate chips,Nestle,fat,false,4.49,24,1,tbsp,70,1,4,9").apply!

    assert_equal [ nil, "Nestle" ], catalog.where(ingredient: "Chocolate chips").order(:id).pluck(:brand)
  end

  test "bad rows are skipped with reasons, and the rest still import" do
    rows = import(
      ",,fat,false,1,1,1,tbsp,1,1,1,1",
      "Butter,,fats,maybe,$4.50,eight,,,100,0,11,0",
      "Flour,,grain,false,2.99,40,0.25,cup,110,3,0,23",
      "flour,,grain,false,2.99,40,0.25,cup,110,3,0,23"
    ).tap(&:apply!).rows

    assert_equal [ :invalid, :invalid, :create, :invalid ], rows.map(&:action)
    assert_includes rows[0].problems, "no ingredient name"
    butter = rows[1].problems.join(" | ")
    assert_match "family \"fats\" isn't one of", butter
    assert_match "organic \"maybe\" isn't true or false", butter
    assert_match "unit_servings \"eight\" isn't a whole number", butter
    assert_match "nutrition facts need a serving_size", butter
    assert_match "same ingredient as line 4", rows[3].problems.first
    assert_equal [ "Flour" ], catalog.pluck(:ingredient)
  end

  test "rows worth a look carry notes but still import" do
    rows = import("BBQ sauce,,,false,3.29,17,2,Envelope,70,0,0,17").tap(&:apply!).rows

    assert_equal :create, rows.first.action
    assert_includes rows.first.notes, "will be saved as \"Bbq sauce\""
    assert_match "isn't one of the recipe page's units", rows.first.notes.join
  end

  test "households' own ingredients are never matched or touched" do
    theirs = households(:one).ingredients.create!(ingredient: "Chocolate chips", unit_price: 1)

    import("Chocolate chips,,fat,false,3.49,24,1,tbsp,70,1,4,9").apply!

    assert_equal 1.0, theirs.reload.unit_price
    assert catalog.exists?(ingredient: "Chocolate chips")
  end

  test "a file missing columns is refused" do
    file = Tempfile.new([ "catalog", ".csv" ]).tap { |f| f.write("ingredient,family\nFlour,grain\n"); f.close }

    error = assert_raises(Ingredient::CatalogImport::HeaderError) { Ingredient::CatalogImport.new(file.path).rows }
    assert_match "missing columns: brand", error.message
  ensure
    file&.unlink
  end

  test "the checked-in catalog file imports cleanly" do
    rows = Ingredient::CatalogImport.new(Rails.root.join("db/ingredients.csv")).rows

    assert_empty rows.select(&:invalid?).map { |row| [ row.line, row.name, row.problems ] }
  end
end
