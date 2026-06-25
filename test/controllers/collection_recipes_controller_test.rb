require "test_helper"

class CollectionRecipesControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get collection_recipes_create_url
    assert_response :success
  end

  test "should get update" do
    get collection_recipes_update_url
    assert_response :success
  end

  test "should get delete" do
    get collection_recipes_delete_url
    assert_response :success
  end
end
