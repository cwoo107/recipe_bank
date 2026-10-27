require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:three).tap { |user| user.update!(app_admin: true) } # carol, owner of household two
    sign_in @admin
  end

  test "the list searches by email, name or household and filters by sign-in" do
    users(:two).identities.create!(provider: "google_oauth2", uid: "bob-google")

    get admin_users_path
    assert_select "#admin_users tbody tr", count: 3

    get admin_users_path(q: "doe household")
    assert_select "#admin_users tbody tr", count: 2
    assert_select "#admin_users", text: /alice@example.com/

    get admin_users_path(q: "BOB")
    assert_select "#admin_users tbody tr", count: 1
    assert_select "#admin_users", text: /Limited/

    get admin_users_path(sign_in: "google_oauth2")
    assert_select "#admin_users tbody tr", count: 1
    assert_select "#admin_users", text: /bob@example.com.*Password and Google/m
  end

  test "a user's page shows their account and the way to view as them" do
    get admin_user_path(users(:two))
    assert_response :success
    assert_select "h1", text: "bob@example.com"
    assert_select "#admin_account", text: /Doe Household/
    assert_select "#admin_impersonate form[action=?]", admin_user_impersonation_path(users(:two))
  end

  test "another admin's page has no view-as button" do
    get admin_user_path(@admin)
    assert_select "#admin_impersonate form", count: 0
  end

  test "the overview loads, with the admin navbar instead of the household one" do
    RecipeImportJob.create!(user: users(:one), status: "failed", error_message: "Couldn't read that page")

    get admin_root_path
    assert_response :success
    assert_select "#admin_navbar"
    assert_select "#admin_billing_counts"
    assert_select "#admin_failures", text: /Recipe import failed.*alice@example.com.*Couldn't read that page/m
  end

  test "the overview copes with older imports that have no user" do
    RecipeImportJob.insert_all!([ { user_id: nil, status: "failed", created_at: Time.current, updated_at: Time.current } ])

    get admin_root_path
    assert_response :success
    assert_select "#admin_failures", text: /Recipe import failed.*no user/m
  end
end
