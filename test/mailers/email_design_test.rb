require "test_helper"

class EmailDesignTest < ActionMailer::TestCase
  setup do
    @bob = users(:two) # member "Bob" of the Doe Household
  end

  test "invitations welcome people to the household with a set-password link" do
    email = HouseholdMailer.invitation(@bob, "tok123", household: households(:one))

    assert_equal [ @bob.email ], email.to
    assert_equal "You're invited to join Doe Household on HomemakersHaven", email.subject
    assert_match "HomemakersHaven <no-reply@example.com>", email[:from].to_s

    html = email.html_part.body.to_s
    assert_match "invited, Bob", html
    assert_match "reset_password_token=tok123", html
    assert_match "Set my password", html
    assert_match "#5f734c", html, "brand colours via the layout"
    assert_match "6 hours", html

    assert_match "reset_password_token=tok123", email.text_part.body.to_s
  end

  test "password reset emails use the branded layout, in HTML and plain text" do
    email = Devise::Mailer.reset_password_instructions(@bob, "tok456")

    assert_equal "Reset your HomemakersHaven password", email.subject
    html = email.html_part.body.to_s
    assert_match "Hi Bob,", html
    assert_match "Choose a new password", html
    assert_match "Homemakers</span>", html
    assert_match "reset_password_token=tok456", email.text_part.body.to_s
  end

  test "adding a member with an email sends the invitation, not a reset email" do
    assert_emails 1 do
      households(:one).invite_member(name: "Teen", email: "teen@example.com")
    end
    assert_match "You're invited", ActionMailer::Base.deliveries.last.subject
  end

  test "giving an existing member a login sends the invitation too" do
    kid = households(:one).invite_member(name: "Kid")
    assert_emails 1 do
      households(:one).give_login(kid, email: "kid@example.com")
    end
    assert_match "invited, Kid", ActionMailer::Base.deliveries.last.html_part.body.to_s
  end

  test "a household name without 'household' in it reads naturally" do
    assert_equal "the Anderson household", Household.new(family_name: "Anderson").display_name
    assert_equal "Alice's Household", Household.new(family_name: "Alice's Household").display_name
  end
end
