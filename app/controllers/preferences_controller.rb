# Display preferences for the signed-in user. Kept separate from Devise's
# registration update so toggling a view setting doesn't require re-entering
# the current password.
class PreferencesController < ApplicationController
  def update
    if current_user.update(preference_params)
      redirect_back_or_to edit_user_registration_path, notice: "Preferences saved.", status: :see_other
    else
      redirect_back_or_to edit_user_registration_path, alert: "Couldn't save preferences.", status: :see_other
    end
  end

  private

  def preference_params
    params.expect(user: [:compact_meals_view])
  end
end
