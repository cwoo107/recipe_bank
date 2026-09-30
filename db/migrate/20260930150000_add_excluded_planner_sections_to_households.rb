# Which "Plan your week" steps a household has turned off (Dashboard section
# keys, e.g. ["todos"]). Stored as what's excluded rather than what's
# included, so a planning area added later shows up for everyone by default.
class AddExcludedPlannerSectionsToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :excluded_planner_sections, :json, default: [], null: false
  end
end
