class AddWeekStartDayToHouseholds < ActiveRecord::Migration[8.1]
  def change
    # Day every week in the household starts on, as a Ruby wday
    # (0 = Sunday .. 6 = Saturday). Defaults to Monday, matching how weeks
    # were keyed before this was configurable.
    add_column :households, :week_start_day, :integer, default: 1, null: false
  end
end
