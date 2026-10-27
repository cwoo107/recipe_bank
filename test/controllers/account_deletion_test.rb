require "test_helper"
require "minitest/mock"

# Deleting an account: "Delete Account" typed to confirm; recipes and
# ingredients pass to the Deleted Users placeholder with who they came from;
# an owner's household goes with them, a member's stays. User::AccountDeletion.
class AccountDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)   # owns household one
    @bob   = users(:two)   # a member of household one
    @household = households(:one)
    User.deleted_users # made up front, so it doesn't count in User.count changes
  end

  def delete_account(confirmation: "Delete Account")
    delete user_registration_url, params: { confirmation: }
  end

  test "the account settings page has the confirmation dialog" do
    sign_in @alice
    get edit_user_registration_url
    assert_select "dialog form[action=?] input[name=confirmation]", user_registration_path
    assert_select "dialog button[type=submit][disabled]", text: "Delete my account"
  end

  test "nothing is deleted without the phrase typed exactly" do
    sign_in @alice
    [ "", "delete account", "Delete" ].each do |typed|
      assert_no_difference "User.count" do
        delete_account(confirmation: typed)
      end
      assert_redirected_to edit_user_registration_url
    end
  end

  test "an owner's account, household and its data go; recipes and ingredients pass to the placeholder" do
    recipe     = @alice.recipes.create!(title: "Alice's chili", visibility: "public")
    bobs_dish  = @bob.recipes.create!(title: "Bob's bread")
    ingredient = @household.ingredients.create!(ingredient: "Ancho chile", created_by: @alice)
    bobs_item  = @household.ingredients.create!(ingredient: "Rye flour", created_by: @bob)
    other_meal = households(:two).meals.create!(recipe:, user: users(:three), meal_name: "Dinner", date: Date.current, servings: 2)
    sign_in @alice

    assert_difference -> { User.count } => -1, -> { Household.where(id: @household.id).count } => -1 do
      delete_account
    end
    assert_redirected_to root_url
    assert_not User.exists?(@alice.id)
    assert_equal 0, Meal.where(household_id: @household.id).count
    assert_not HouseholdMember.exists?(user_id: @bob.id)

    placeholder = User.deleted_users
    recipe.reload
    assert_equal [ placeholder, @alice.id, "alice@example.com" ], [ recipe.user, recipe.former_user_id, recipe.former_user_email ]
    assert_equal "public", recipe.visibility
    assert other_meal.reload.persisted?, "another household's meal of the recipe stays"

    ingredient.reload
    assert_equal [ placeholder.household, placeholder, @alice.id, "alice@example.com" ],
                 [ ingredient.household, ingredient.created_by, ingredient.former_user_id, ingredient.former_user_email ]
    assert_equal [ @bob.id, "bob@example.com" ], [ bobs_item.reload.former_user_id, bobs_item.former_user_email ]

    # Bob keeps his login and his own recipes.
    assert_equal @bob, bobs_dish.reload.user
  end

  test "a member's account goes, but the household and what they added stay" do
    recipe     = @bob.recipes.create!(title: "Bob's bread")
    ingredient = @household.ingredients.create!(ingredient: "Rye flour", created_by: @bob)
    sign_in @bob

    assert_difference "User.count", -1 do
      delete_account
    end
    assert Household.exists?(@household.id)
    assert_equal @alice, recipe.reload.user # handed off like a removed member's
    ingredient.reload
    assert_equal [ @household, User.deleted_users, @bob.id, "bob@example.com" ],
                 [ ingredient.household, ingredient.created_by, ingredient.former_user_id, ingredient.former_user_email ]
  end

  test "an app admin's audit trail stays, credited to the placeholder" do
    @alice.update!(app_admin: true)
    AdminAction.create!(admin: @alice, household: households(:two), action: "comp")
    sign_in @alice

    assert_difference "User.count", -1 do
      delete_account
    end
    assert_equal [ User.deleted_users.id ], AdminAction.pluck(:admin_id).uniq
  end

  test "the placeholder is made once, comped, and can't sign in" do
    placeholder = User.deleted_users
    assert_equal placeholder, User.deleted_users
    assert placeholder.household.comped?
    assert_not placeholder.active_for_authentication?
  end

  test "a subscription Stripe won't cancel stops the deletion" do
    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
    sign_in @alice

    StripeBilling.stub(:cancel_subscription, ->(_) { raise Stripe::APIConnectionError, "down" }) do
      assert_no_difference "User.count" do
        delete_account
      end
    end
    assert_redirected_to edit_user_registration_url
    assert_match "couldn't cancel your subscription", flash[:alert]
  end

  test "an owner's live subscription is cancelled" do
    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
    cancelled = []
    sign_in @alice

    StripeBilling.stub(:cancel_subscription, ->(household) { cancelled << household.stripe_subscription_id }) do
      delete_account
    end
    assert_equal [ "sub_123" ], cancelled
    assert_not User.exists?(@alice.id)
  end
end
