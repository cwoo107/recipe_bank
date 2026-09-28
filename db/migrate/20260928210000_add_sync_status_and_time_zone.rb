class AddSyncStatusAndTimeZone < ActiveRecord::Migration[8.1]
  def change
    # What went wrong on the last sync attempt (nil when it worked), and when
    # it was tried — last_synced_at stays the last *successful* sync.
    add_column :calendar_sources, :last_sync_error, :text
    add_column :calendar_sources, :last_sync_attempted_at, :datetime

    # The household's time zone (IANA name, e.g. "America/Denver"). Taken from
    # an admin's browser the first time one signs in, editable in settings.
    # Used for every page and for calendar syncing, so all-day events and
    # floating times land on the right day.
    add_column :households, :time_zone, :string
  end
end
