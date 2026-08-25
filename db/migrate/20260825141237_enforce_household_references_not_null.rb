class EnforceHouseholdReferencesNotNull < ActiveRecord::Migration[8.1]
  def change
    change_column_null :meals,            :household_id, false
    change_column_null :todos,            :household_id, false
    change_column_null :grocery_lists,    :household_id, false
    change_column_null :calendar_sources, :household_id, false
    change_column_null :calendar_events,  :household_id, false
  end
end
