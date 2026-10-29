# Hourly (config/schedule.yml): clears uploads that were never read. A
# recipe or receipt upload waits on its import or scan only until the
# worker reads it (RecipeImporter#perform_from_file, ReceiptScanner#perform
# clear it then, whether or not reading succeeds) — but one whose job never
# ran (the enqueue failed, or the worker was down past its retries) would
# otherwise stay in the database for good. Anything still waiting after
# STALE_AFTER is cleared, and its import or scan marked failed so the page
# says to upload it again.
class PurgeStaleUploadsJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 1.hour
  MESSAGE = "The upload expired before it could be read — please upload it again.".freeze

  def perform
    cutoff = STALE_AFTER.ago
    now    = Time.current

    imports = RecipeImportJob.where.not(source_file: nil).where(created_at: ...cutoff)
    imports.where(status: "pending").update_all(status: "failed", failed_step: "pending", error_message: MESSAGE,
                                                current_step: "Error: #{MESSAGE}", updated_at: now)
    cleared = imports.update_all(source_file: nil, updated_at: now)

    scans = ReceiptScan.where.not(source_file: nil).where(created_at: ...cutoff)
    scans.where(status: "pending").update_all(status: "failed", error_message: MESSAGE, updated_at: now)
    cleared += scans.update_all(source_file: nil, updated_at: now)

    Rails.logger.info "PurgeStaleUploadsJob: cleared #{cleared} unread upload(s)" if cleared.positive?
  end
end
