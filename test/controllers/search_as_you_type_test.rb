require "test_helper"

# The recipe and ingredient search boxes submit as you type
# (search_controller.js) into a results frame, so the box itself isn't
# re-rendered and keeps focus.
class SearchAsYouTypeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "the recipe search submits into the results frame as you type" do
    get recipes_url(query: "soup")

    assert_select "form[data-controller=search][data-turbo-frame=recipes-results][data-turbo-action=replace]" do
      assert_select "input[name=query][data-action='input->search#submit'][value=soup]"
    end
    # Links in the results still open full pages.
    assert_select "turbo-frame#recipes-results[target=_top]"
  end

  test "the ingredient search submits into the results frame without changing the URL" do
    get ingredients_url(query: "milk")

    assert_select "form[data-controller=search][data-turbo-frame=ingredients-results]:not([data-turbo-action])" do
      assert_select "input[name=query][data-action='input->search#submit'][value=milk]"
    end
    assert_select "turbo-frame#ingredients-results[target=ingredient]"
  end
end
