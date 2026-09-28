# Per-item permission checks shared by controllers (via `helpers.`) and views,
# so a button is only shown when the action behind it would be allowed.
# Owners and admins can do everything; see ApplicationController.
module PermissionsHelper
  # Edit the content of / delete a to-do: admins, or whoever created it.
  def todo_editable?(todo)
    household_admin? || todo.user_id == current_user.id
  end

  # Change a to-do's status (drag between columns): also the person it's
  # assigned to.
  def todo_movable?(todo)
    todo_editable?(todo) || (current_member.present? && todo.assignee_id == current_member.id)
  end

  # Tick a weekly chore complete: admins, or the person it's assigned to.
  def weekly_chore_completable?(weekly_chore)
    household_admin? || (current_member.present? && weekly_chore.assignee_id == current_member.id)
  end
end
