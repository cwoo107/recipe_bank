require "test_helper"

class RecipeImportsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get recipe_imports_new_url
    assert_response :success
  end

  test "should get create" do
    get recipe_imports_create_url
    assert_response :success
  end
end
