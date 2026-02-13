require "test_helper"

class NutritionFactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nutrition_fact = nutrition_facts(:one)
  end

  test "should get index" do
    get nutrition_facts_url
    assert_response :success
  end

  test "should get new" do
    get new_nutrition_fact_url
    assert_response :success
  end

  test "should create nutrition_fact" do
    assert_difference("NutritionFact.count") do
      post nutrition_facts_url, params: { nutrition_fact: { ingredient_id: @nutrition_fact.ingredient_id, protein: @nutrition_fact.protein, serving_size: @nutrition_fact.serving_size, serving_unit: @nutrition_fact.serving_unit, total_carb: @nutrition_fact.total_carb, total_fat: @nutrition_fact.total_fat } }
    end

    assert_redirected_to nutrition_fact_url(NutritionFact.last)
  end

  test "should show nutrition_fact" do
    get nutrition_fact_url(@nutrition_fact)
    assert_response :success
  end

  test "should get edit" do
    get edit_nutrition_fact_url(@nutrition_fact)
    assert_response :success
  end

  test "should update nutrition_fact" do
    patch nutrition_fact_url(@nutrition_fact), params: { nutrition_fact: { ingredient_id: @nutrition_fact.ingredient_id, protein: @nutrition_fact.protein, serving_size: @nutrition_fact.serving_size, serving_unit: @nutrition_fact.serving_unit, total_carb: @nutrition_fact.total_carb, total_fat: @nutrition_fact.total_fat } }
    assert_redirected_to nutrition_fact_url(@nutrition_fact)
  end

  test "should destroy nutrition_fact" do
    assert_difference("NutritionFact.count", -1) do
      delete nutrition_fact_url(@nutrition_fact)
    end

    assert_redirected_to nutrition_facts_url
  end
end
