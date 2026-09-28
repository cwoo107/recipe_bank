class EncryptCalendarSourceSecrets < ActiveRecord::Migration[8.1]
  # Re-saves existing calendars so their feed links (and any tokens) are
  # encrypted now that CalendarSource `encrypts` them. Needs the Active Record
  # encryption keys in credentials.
  def up
    CalendarSource.reset_column_information
    CalendarSource.find_each(&:encrypt)
  end

  def down
    CalendarSource.find_each(&:decrypt)
  end
end
