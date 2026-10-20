require "test_helper"

class IngredientsHelperTest < ActionView::TestCase
  test "every family has tag colors" do
    assert_equal Ingredient::FAMILIES.keys.sort, IngredientsHelper::FAMILY_TAG_CLASSES.keys.sort
  end

  test "tags a family with its label" do
    tag = ingredient_family_tag("canned")
    assert_includes tag, "Canned &amp; Jarred"
    assert_includes tag, "bg-olive-300"
  end

  test "an unknown family still gets a neutral tag" do
    assert_includes ingredient_family_tag("pantry"), "Pantry"
  end
end
