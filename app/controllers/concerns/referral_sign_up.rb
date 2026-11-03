# Sign-up through someone's share link (ReferralsController puts its code in
# the session): like a beta invite, it opens sign-up before launch, and the
# new household is recorded as referred (Referral). Shared by the sign-up
# form and Google / Apple sign-up.
module ReferralSignUp
  extend ActiveSupport::Concern

  private

  def referral_sign_up?
    code = session[:referral_code]
    code.present? && Household.exists?(referral_code: code)
  end

  def record_referral(user)
    code = session.delete(:referral_code)
    Referral.record(code, household: user.household) if user.persisted?
  end
end
