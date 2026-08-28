require "application_system_test_case"

class TurboConfirmTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  test "cancelling the custom confirm dialog leaves the record intact" do
    meal = meals(:one)
    login_as users(:one), scope: :user
    visit meals_url(date: meal.date.beginning_of_week)

    assert_no_selector "dialog[open]"
    click_button "Remove", match: :first

    within "dialog[data-controller='turbo-confirm']" do
      assert_text "Remove this meal?"
      click_button "Cancel"
    end

    assert_no_selector "dialog[open]"
    assert Meal.exists?(meal.id)
  end

  test "accepting the custom confirm dialog proceeds with the action" do
    meal = meals(:one)
    login_as users(:one), scope: :user
    visit meals_url(date: meal.date.beginning_of_week)

    click_button "Remove", match: :first

    within "dialog[data-controller='turbo-confirm']" do
      assert_text "Remove this meal?"
      click_button "Confirm"
    end

    assert_no_selector "dialog[open]"
    assert_not Meal.exists?(meal.id)
  end
end
