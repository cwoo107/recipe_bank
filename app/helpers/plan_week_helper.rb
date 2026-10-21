module PlanWeekHelper
  # Where a planner step stands, for the progress bar (desktop) and the
  # step accordion (mobile): :done, :skipped, :current or :upcoming.
  def plan_step_state(section, current_key)
    if section.status == "done"
      :done
    elsif section.status == "skipped"
      :skipped
    elsif section.key == current_key
      :current
    else
      :upcoming
    end
  end
end
