
class CreateCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_events do |t|
      t.references :calendar_source, null: false, foreign_key: true
      t.references :user,            null: false, foreign_key: true
      t.string     :title,           null: false
      t.text       :description
      t.string     :location
      t.datetime   :starts_at,       null: false
      t.datetime   :ends_at,         null: false
      t.boolean    :all_day,         null: false, default: false
      t.string     :external_uid     # provider's event UID
      t.string     :recurrence_rule  # RRULE string
      t.string     :status,          default: "confirmed"  # confirmed, tentative, cancelled
      t.string     :url
      t.timestamps
    end

    add_index :calendar_events, [:user_id, :starts_at]
    add_index :calendar_events, [:calendar_source_id, :starts_at]
    add_index :calendar_events, :external_uid
    add_index :calendar_events, :starts_at
    add_index :calendar_events, :ends_at
  end
end