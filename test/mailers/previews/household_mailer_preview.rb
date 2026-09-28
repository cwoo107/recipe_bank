# Preview at http://localhost:3000/rails/mailers/household_mailer
class HouseholdMailerPreview < ActionMailer::Preview
  def invitation
    member = HouseholdMember.where.not(user_id: nil).where.not(user_id: Household.select(:owner_id)).first
    user   = member&.user || User.first
    HouseholdMailer.invitation(user, "preview-token", household: user.household)
  end
end
