# Adds days to a household's free trial (Household#extend_trial!).
class Admin::TrialExtensionsController < Admin::BaseController
  MAX_DAYS = 365

  rescue_from Stripe::StripeError, StripeBilling::NotConfigured do |error|
    redirect_to admin_household_path(params[:household_id]), alert: "Stripe error: #{error.message}", status: :see_other
  end

  def create
    household = Household.find(params[:household_id])
    days = params[:days].to_i

    if !household.trial_extendable?
      alert = "This household is paying — use credits or refunds in Stripe instead."
    elsif !days.between?(1, MAX_DAYS)
      alert = "Extend by between 1 and #{MAX_DAYS} days."
    else
      household.extend_trial!(by: days.days, admin: current_user, note: params[:note].presence)
      notice = "Trial extended by #{helpers.pluralize(days, 'day')}, to #{I18n.l(household.trial_ends_at.to_date, format: :long)}."
    end

    redirect_to admin_household_path(household), notice:, alert:, status: :see_other
  end
end
