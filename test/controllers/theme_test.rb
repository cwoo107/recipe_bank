require "test_helper"

# Light by default; a visitor's choice from the marketing site's switch is a
# cookie, a signed-in user's is saved on their account.
class ThemeTest < ActionDispatch::IntegrationTest
  test "pages are light by default" do
    get root_url
    assert_select "html[data-theme=light]:not(.dark)"
    assert_select "[data-controller=theme] button[aria-pressed=true][data-theme-theme-param=light]"
  end

  test "a visitor's choice is remembered in a cookie" do
    patch theme_url, params: { theme: "dark" }, as: :json
    assert_response :no_content

    get root_url
    assert_select "html.dark[data-theme=dark]"

    patch theme_url, params: { theme: "system" }, as: :json
    get pricing_url
    assert_select "html[data-theme=system]:not(.dark)" # the head script decides from the device
  end

  test "a signed-in user's choice is saved on their account and wins over the cookie" do
    user = users(:one)
    sign_in user
    patch theme_url, params: { theme: "dark" }, as: :json
    assert_equal "dark", user.reload.theme

    cookies[:theme] = "light"
    get meals_url
    assert_select "html.dark[data-theme=dark]"
  end

  test "Account settings saves the theme" do
    user = users(:one)
    sign_in user
    get edit_user_registration_url
    assert_select "input[type=radio][name='user[theme]'][value=light][checked]"

    patch preferences_url, params: { user: { theme: "system" } }
    assert_equal "system", user.reload.theme
    assert_equal "system", cookies[:theme]
  end

  test "an unknown theme is refused" do
    patch theme_url, params: { theme: "neon" }, as: :json
    assert_response :unprocessable_entity
    get root_url
    assert_select "html[data-theme=light]"

    sign_in users(:one)
    patch preferences_url, params: { user: { theme: "neon" } }
    assert_equal "light", users(:one).reload.theme
  end
end
