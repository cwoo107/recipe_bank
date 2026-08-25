class AddHouseholdReferencesToPlanningTables < ActiveRecord::Migration[8.1]
  # NOTE: existing rows in these tables, so this is split into
  # add column (null: true) -> backfill household_id -> change_column_null.
  def change
    add_reference :meals,            :household, null: true, foreign_key: true
    add_reference :todos,            :household, null: true, foreign_key: true
    add_reference :grocery_lists,    :household, null: true, foreign_key: true
    add_reference :calendar_sources, :household, null: true, foreign_key: true
    add_reference :calendar_events,  :household, null: true, foreign_key: true

    add_index :todos,            [ :household_id, :status ]
    add_index :todos,            [ :household_id, :status, :position ]
    add_index :todos,            [ :household_id, :status, :start_date ]
    add_index :calendar_sources, [ :household_id, :position ]
    add_index :calendar_events,  [ :household_id, :starts_at ]
  end
end
