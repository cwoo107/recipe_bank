class ReceiptScansController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_receipt_scan, only: %i[show update apply]

  # Every scan runs on Claude, so a household can only start so many an
  # hour. Counted per process (the cache store is in memory).
  rate_limit to: 20, within: 1.hour, only: :create,
             by: -> { current_household.id },
             with: -> { redirect_to new_receipt_scan_path, alert: "That's a lot of receipts at once — please try again in a little while." }

  # Receipts are read on Sidekiq (ProcessReceiptScanJob), and the scan page
  # streams its progress as Turbo broadcasts over Redis.

  # Uploads wait in the database until the worker reads them. Base64 for
  # Claude grows a file by a third, and its requests top out at 32 MB.
  MAX_UPLOAD_SIZE = 20.megabytes

  # Starts on the week the grocery list was showing (?date=).
  def new
    @date = week_from(params[:date])
  end

  def create
    @date = week_from(params[:week_of])
    file  = params[:file]

    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return redirect_to new_receipt_scan_path(date: @date), alert: "Please choose a photo of your receipt."
    end

    if file.size > MAX_UPLOAD_SIZE
      return redirect_to new_receipt_scan_path(date: @date), alert: "That file is too large — please upload one under #{MAX_UPLOAD_SIZE / 1.megabyte} MB."
    end

    # Judged by the file's contents, not the type the browser claims for it.
    content_type = ClaudeFileContent.content_type_of(file)
    unless content_type
      return redirect_to new_receipt_scan_path(date: @date), alert: "Unsupported file type. Please upload a photo (JPEG, PNG, WebP) or a PDF."
    end

    # The worker may be in another container, so the upload travels with the
    # scan rather than on this server's disk; it's cleared once read.
    scan = current_household.receipt_scans.create!(
      user: current_user,
      week_of: @date,
      source_file: file.read,
      source_content_type: content_type
    )

    ProcessReceiptScanJob.perform_later(scan.id)

    redirect_to receipt_scan_path(scan)
  end

  def show; end

  # The review's Previous/Next week buttons: which week's list to check off.
  def update
    unless @receipt_scan.applied?
      @receipt_scan.update!(week_of: week_from(params.dig(:receipt_scan, :week_of)))
    end

    redirect_to receipt_scan_path(@receipt_scan), status: :see_other
  end

  def apply
    # Claimed atomically, so a second submit can't apply the receipt twice —
    # and in the same transaction, so a failed apply doesn't leave it claimed.
    result = ReceiptScan.transaction do
      next unless @receipt_scan.claim_application!

      @receipt_scan.apply!(confirmed: params[:confirmed], price_updates: params[:price_updates])
    end

    unless result
      return redirect_to receipt_scan_path(@receipt_scan), alert: "This receipt isn't waiting on review."
    end

    notice = "Checked off #{helpers.pluralize(result[:checked], 'item')} for the week of #{@receipt_scan.week_of.strftime('%b %d')}."
    notice += " Updated #{helpers.pluralize(result[:prices], 'price')}." if result[:prices].positive?

    redirect_to grocery_lists_path(date: @receipt_scan.week_of), notice: notice, status: :see_other
  end

  private

  def set_receipt_scan
    @receipt_scan = current_household.receipt_scans.find(params[:id])
  end

  # The start of the week containing `value` (a date string), or this week.
  def week_from(value)
    (value.present? ? Date.parse(value) : Time.zone.today).beginning_of_week
  rescue Date::Error
    Time.zone.today.beginning_of_week
  end
end
