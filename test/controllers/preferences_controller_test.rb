require "test_helper"

class PreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "turns compact meals view on and redirects back" do
    patch preferences_url, params: { user: { compact_meals_view: "1" } },
                           headers: { "HTTP_REFERER" => meals_url }

    assert @user.reload.compact_meals_view?
    assert_redirected_to meals_url
  end

  test "turns compact meals view off" do
    @user.update!(compact_meals_view: true)

    patch preferences_url, params: { user: { compact_meals_view: "0" } }

    assert_not @user.reload.compact_meals_view?
    assert_redirected_to edit_user_registration_url
  end

  test "does not require current password" do
    patch preferences_url, params: { user: { compact_meals_view: "1", email: "hijack@example.com" } }

    assert @user.reload.compact_meals_view?
    assert_not_equal "hijack@example.com", @user.email
  end

  test "requires sign in" do
    sign_out @user
    patch preferences_url, params: { user: { compact_meals_view: "1" } }

    assert_redirected_to new_user_session_url
  end

  test "account settings page has the compact meals view field" do
    get edit_user_registration_url

    assert_response :success
    assert_select "form[action='#{preferences_path}'] input[type=checkbox][name='user[compact_meals_view]']"
  end
end
