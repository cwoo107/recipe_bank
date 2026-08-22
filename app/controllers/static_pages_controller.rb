class StaticPagesController < ApplicationController
  skip_before_action :authenticate_user!
  layout "marketing"

  def home
    redirect_to meals_path if user_signed_in?
  end

  def pricing; end
  def meal_planning; end
  def grocery_lists; end
  def recipes; end
  def todos; end
  def calendar; end
end
