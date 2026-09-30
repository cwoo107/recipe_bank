require "test_helper"

class RecipeExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
  end

  test "the owner downloads a PDF of every recipe the household's members created" do
    Recipe.create!(title: "Alice's Soup 🍲", user: users(:one)).steps.create!(content: "Simmer")
    Recipe.create!(title: "Bob's Bread", user: users(:two))
    Recipe.create!(title: "Carol's Cake", user: users(:three)) # another household

    pdf = RecipeBookPdf.new(household: @household)
    authors = pdf.recipes_by_author.to_h
    assert_includes authors["Alice"].map(&:title), "Alice's Soup 🍲"
    assert_includes authors["Bob"].map(&:title), "Bob's Bread"
    assert_not_includes authors.values.flatten.map(&:title), "Carol's Cake"
    assert_equal "Alice", authors.keys.first, "owner first"

    sign_in users(:one)
    get household_recipe_export_path(format: :pdf)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match(/attachment; filename="doe-household-recipes-#{Date.current.iso8601}.pdf"/, response.headers["Content-Disposition"])
    assert response.body.start_with?("%PDF")
  end

  test "the household page offers the export to the owner only" do
    sign_in users(:one)
    get household_path
    assert_select "#recipe_export a[href='#{household_recipe_export_path(format: :pdf)}']"

    sign_in users(:two)
    get household_path
    assert_select "#recipe_export", count: 0
  end

  test "members can't export" do
    sign_in users(:two)
    get household_recipe_export_path(format: :pdf)
    assert_redirected_to household_path
  end

  test "an empty household still gets a PDF" do
    Recipe.for_household(@household).destroy_all
    sign_in users(:one)
    get household_recipe_export_path(format: :pdf)
    assert_response :success
  end
end
