# The household's time for to-dos — per week, or per day — changed right
# where it's shown: the board's time meter and "Plan your week".
class TodoBudgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_household_admin!

  def update
    if current_household.update(budget_params)
      Todo.broadcast_gantt(current_household)
      redirect_back_or_to todos_path, status: :see_other
    else
      redirect_back_or_to todos_path, alert: current_household.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def budget_params
    params.expect(household: [ :todo_time_period, :todo_hours_per_week, :minutes_per_day ])
  end
end
