# The household's time for to-dos — per week, or per day — changed right
# where it's shown: the board's time meter and "Plan your week".
class TodoBudgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_household_admin!

  def update
    if current_household.update(budget_params)
      Todo.broadcast_gantt(current_household)
      respond_to do |format|
        # Swap just the meter and chart, so the page keeps its scroll.
        format.turbo_stream { @budget = TodoBudget.new(current_household, budget_week) }
        format.html { redirect_back_or_to todos_path, status: :see_other }
      end
    else
      redirect_back_or_to todos_path, alert: current_household.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def budget_params
    params.expect(household: [ :todo_time_period, :todo_hours_per_week, :minutes_per_day ])
  end

  # "Plan your week" may be showing a week other than this one.
  def budget_week
    Date.iso8601(params[:week].to_s).beginning_of_week(current_household.week_start_symbol)
  rescue Date::Error
    Todo.current_week_start(current_household)
  end
end
