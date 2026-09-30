# The owner's "take your recipes with you" download: a PDF of every recipe
# the household's members have created (RecipeBookPdf). Always available —
# including once a trial has run out — so no one's recipes are held hostage.
class RecipeExportsController < ApplicationController
  skip_before_action :require_active_subscription!
  before_action :require_household!
  before_action :require_owner!

  def show
    pdf = RecipeBookPdf.new(household: current_household)
    send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "attachment"
  end

  private

  def require_owner!
    return if current_household.owner?(current_user)

    redirect_to household_path, alert: "Only the account owner can export the household's recipes.", status: :see_other
  end
end
