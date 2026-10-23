# Reads an uploaded grocery receipt (a ReceiptScan record) on Sidekiq —
# enqueued by ReceiptScansController#create. Progress reaches the page as
# Turbo broadcasts over Action Cable (Redis).
#
# Failures aren't retried: ReceiptScanner has already recorded the error on
# the scan for the user to see, and the upload is gone by then. Sidekiq
# still logs the exception.
class ProcessReceiptScanJob < ApplicationJob
  queue_as :default

  discard_on StandardError do |job, error|
    Rails.logger.error "ProcessReceiptScanJob #{job.arguments.inspect} failed: #{error.class}: #{error.message}"
  end

  def perform(receipt_scan_id)
    scan = ReceiptScan.find_by(id: receipt_scan_id)
    return unless scan&.pending?

    ReceiptScanner.new(scan).perform
  end
end
