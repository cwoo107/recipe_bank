class AddDefaultWeekdayToChores < ActiveRecord::Migration[8.1]
  def change
    # Ruby's Date#wday convention: 0 = Sunday .. 6 = Saturday. Set once a
    # chore is dragged onto a specific day, so it can replicate onto that
    # same day every week it's due, rather than requiring a manual re-drag.
    add_column :chores, :default_weekday, :integer
  end
end
