class CreateCalendarSources < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_sources do |t|
      t.references :user,         null: false, foreign_key: true
      t.string     :name,         null: false
      t.string     :provider,     null: false  # google, apple, outlook, ical
      t.string     :color,        null: false, default: "olive"
      t.string     :access_token
      t.string     :refresh_token
      t.datetime   :token_expires_at
      t.string     :external_id   # provider's calendar ID
      t.string     :ical_url      # for iCal/webcal feeds
      t.boolean    :synced,       null: false, default: false
      t.datetime   :last_synced_at
      t.boolean    :visible,      null: false, default: true
      t.integer    :position,     null: false, default: 0
      t.timestamps
    end

    add_index :calendar_sources, [:user_id, :position]
    add_index :calendar_sources, :provider
  end
end