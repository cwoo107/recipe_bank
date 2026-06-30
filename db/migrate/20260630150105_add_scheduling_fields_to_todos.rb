class AddSchedulingFieldsToTodos < ActiveRecord::Migration[8.1]
  def change
    # Durations are stored as a whole number of MINUTES (the canonical unit).
    add_column :todos, :estimated_time_to_complete, :integer
    add_column :todos, :actual_time_to_complete,    :integer

    add_column :todos, :start_date, :datetime
    add_column :todos, :end_date,   :datetime

    add_column :todos, :completed,  :boolean, default: false, null: false

    add_index :todos, [ :user_id, :status, :start_date ]
  end

end
