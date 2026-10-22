require "test_helper"

class GroceryListsHelperTest < ActionView::TestCase
  test "kitchen measures read as fractions, metric as numbers" do
    assert_equal "5 ¼ cups", grocery_amount(5.25, "cup")
    assert_equal "⅓ cup", grocery_amount(0.333, "cup")
    assert_equal "1 cup", grocery_amount(1.0, "cup")
    assert_equal "2 tbsp", grocery_amount(2.0, "tbsp")
    assert_equal "1.4 lbs", grocery_amount(1.4, "lb")
    assert_equal "1000 g", grocery_amount(1000.0, "g")
    assert_equal "3 pieces", grocery_amount(3.0, "piece")
    assert_equal "2", grocery_amount(2.0, nil)
  end
end
