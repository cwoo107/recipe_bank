require "test_helper"

# Tags belong to the household (Tag) — the Recipe tags tab on the Recipes page.
class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = tags(:one) # household :one
    sign_in users(:one) # alice, an admin of household :one
  end

  test "lists only the household's tags, in the Recipe tags tab" do
    get tags_url

    assert_response :success
    assert_select "turbo-frame#tags-index[target=_top]" do
      assert_select "span", text: "Weeknight"
      assert_select "span", text: "Holiday", count: 0 # household :two's
    end
    assert_select "[aria-current=page]", text: "Recipe tags"
  end

  test "another member of the household sees the same tags" do
    sign_in users(:two) # bob, also in household :one
    get tags_url

    assert_select "span", text: "Weeknight"
  end

  test "creating a tag adds it to the household, noting who made it" do
    assert_difference("households(:one).tags.count") do
      post tags_url, params: { tag: { tag: "Sunday supper", color: "#577584" } }
    end

    tag = households(:one).tags.find_by!(tag: "Sunday supper")
    assert_equal users(:one), tag.user
    assert_redirected_to tags_url
  end

  test "names are unique within a household, whatever the capitalization" do
    assert_no_difference("Tag.count") do
      post tags_url, params: { tag: { tag: "weeknight", color: "#577584" } }
    end
    assert_response :unprocessable_entity
  end

  test "another household's tag can't be seen, changed or deleted" do
    other = tags(:two)

    # (Signing in again each time — a 404 response doesn't carry the
    # session cookie on to the next request.)
    get tag_url(other)
    assert_response :not_found

    sign_in users(:one)
    patch tag_url(other), params: { tag: { tag: "Mine now" } }
    assert_response :not_found

    sign_in users(:one)
    assert_no_difference("Tag.count") { delete tag_url(other) }
    assert_equal "Holiday", other.reload.tag
  end

  test "a limited member can look but not change tags" do
    sign_in users(:two) # bob, limited

    assert_no_difference("Tag.count") { post tags_url, params: { tag: { tag: "Nope", color: "#577584" } } }
    patch tag_url(@tag), params: { tag: { tag: "Renamed" } }
    assert_equal "Weeknight", @tag.reload.tag
  end

  test "updating and deleting a tag" do
    patch tag_url(@tag), params: { tag: { tag: "Weeknight dinner" } }
    assert_equal "Weeknight dinner", @tag.reload.tag

    assert_difference("Tag.count", -1) { delete tag_url(@tag) }
    assert_redirected_to tags_url
  end
end
