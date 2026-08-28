class AddMinutesPerDayToHouseholds < ActiveRecord::Migration[8.1]
  def change
    # Replaces the old hardcoded Todo::MINUTES_PER_DAY constant: how many
    # minutes of todo-work capacity each calendar day has, used by the
    # scheduler to turn an estimated_time_to_complete into a day span.
    add_column :households, :minutes_per_day, :integer, null: false, default: 30
  end
end
