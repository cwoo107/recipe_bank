require "test_helper"

# Admin-picked recipes that lead the public browse list.
class FeaturedRecipesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)   # owner of household one
    @carol = users(:three) # owner of household two
    @admin = users(:two).tap { |user| user.update!(app_admin: true) } # bob, member of household one

    @apple  = @carol.recipes.create!(title: "Apple Crumble", visibility: "public")
    @zucchi = @carol.recipes.create!(title: "Zucchini Fritters", visibility: "public", featured: true)
  end

  test "featured recipes lead the public list, tagged and tinted" do
    sign_in @alice
    get recipes_url(scope: "public", sort: "title", direction: "asc")

    assert_response :success
    assert_operator response.body.index("Zucchini Fritters"), :<, response.body.index("Apple Crumble")
    assert_select "tr.bg-\\[\\#5f734c\\]\\/5", count: 1, text: /Zucchini Fritters.*Featured recipe/m
  end

  test "the household list neither reorders nor tags featured recipes" do
    @alice.recipes.create!(title: "Alpha Soup", featured: true)
    @alice.recipes.create!(title: "Beta Soup")
    sign_in @alice
    get recipes_url

    assert_no_match "Featured recipe", response.body
  end

  test "saving a featured recipe gives a copy that isn't featured" do
    sign_in @alice
    post save_to_household_recipe_url(@zucchi)

    copy = Recipe.order(:id).last
    assert_equal @zucchi, copy.source_recipe
    assert_not copy.featured?
    assert @zucchi.reload.featured?
  end

  test "users can't set featured through the recipe form" do
    recipe = @alice.recipes.create!(title: "Mine")
    sign_in @alice
    patch recipe_url(recipe), params: { recipe: { title: "Mine", featured: "1" } }

    assert_not recipe.reload.featured?
  end

  test "non-admins get a 404" do
    sign_in @alice
    get admin_featured_recipes_path
    assert_response :not_found

    sign_in @alice
    post admin_featured_recipes_path, params: { recipe_id: @apple.id }
    assert_response :not_found
    assert_not @apple.reload.featured?
  end

  test "admins feature and unfeature public recipes" do
    sign_in @admin
    get admin_featured_recipes_path(q: "apple")
    assert_select "#admin_featured_recipes", text: /Zucchini Fritters/
    assert_select "#admin_featured_recipe_results", text: /Apple Crumble/

    post admin_featured_recipes_path, params: { recipe_id: @apple.id }
    assert @apple.reload.featured?

    delete admin_featured_recipe_path(@zucchi)
    assert_not @zucchi.reload.featured?
  end

  test "private recipes can't be featured" do
    secret = @carol.recipes.create!(title: "Secret", visibility: "private")
    sign_in @admin
    post admin_featured_recipes_path, params: { recipe_id: secret.id }

    assert_response :not_found
    assert_not secret.reload.featured?
  end
end
