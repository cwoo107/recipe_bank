# Re-syncs every linked calendar (scheduled in config/schedule.yml).
class SyncAllCalendarsJob < ApplicationJob
  queue_as :default

  def perform
    # Feed links are encrypted, so filter in Ruby rather than in SQL.
    CalendarSource.find_each do |source|
      CalendarSyncJob.perform_later(source.id) if source.syncable?
    end
  end
end
