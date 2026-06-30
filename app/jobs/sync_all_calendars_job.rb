class SyncAllCalendarsJob < ApplicationJob
  queue_as :default

  def perform
    CalendarSource.where.not(ical_url: [nil, ""]).find_each do |source|
      CalendarSyncJob.perform_later(source.id)
    end
  end
end