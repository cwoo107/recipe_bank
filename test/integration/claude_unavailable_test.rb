require "test_helper"
require "minitest/mock"

# When Claude can't be used (out of credits, overloaded…), users are told the
# feature is unavailable; the API's own error is kept for admins.
class ClaudeUnavailableTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # The error from the report: the account ran out of API credits.
  def out_of_credits
    Anthropic::Errors::BadRequestError.new(
      url: URI("https://api.anthropic.com/v1/messages"), status: 400, headers: {}, request: nil, response: nil,
      body: { type: "error", request_id: "req_011Cgf2UsQEYTySx6bmJSo9h",
              error: { type: "invalid_request_error",
                       message: "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits." } },
      message: "{url: \"https://api.anthropic.com/v1/messages\", status: 400, body: …}"
    )
  end

  # A real (1×1) image, so the upload gets as far as calling Claude.
  def tiny_png
    require "vips"
    Vips::Image.black(1, 1).pngsave_buffer
  end

  FakeMessages = Struct.new(:error) { def create(**) = raise(error) }
  FakeClient   = Struct.new(:messages)

  def without_credits(&)
    Anthropic::Client.stub(:new, ->(**) { FakeClient.new(FakeMessages.new(out_of_credits)) }, &)
  end

  test "the admin's copy of the error leads with the API's explanation" do
    error = ClaudeUnavailableError.from(out_of_credits)

    assert_equal "Claude API error 400 invalid_request_error: Your credit balance is too low to access the Anthropic API. " \
                 "Please go to Plans & Billing to upgrade or purchase credits. · request req_011Cgf2UsQEYTySx6bmJSo9h", error.message
  end

  test "a receipt upload tells the user it's unavailable, and keeps the reason for admins" do
    scan = households(:one).receipt_scans.create!(user: users(:one), week_of: Date.current.beginning_of_week,
                                                  source_file: tiny_png, source_content_type: "image/png")

    without_credits { ProcessReceiptScanJob.perform_now(scan.id) }

    scan.reload
    assert scan.failed?
    assert_equal "Receipt upload service is currently unavailable. Please try again later.", scan.error_message
    assert_match "Your credit balance is too low", scan.error_detail

    sign_in users(:one)
    get receipt_scan_url(scan)
    assert_match "Receipt upload service is currently unavailable", response.body
    assert_no_match "credit balance", response.body
  end

  test "a recipe file import tells the user it's unavailable, and keeps the reason for admins" do
    job = users(:one).recipe_import_jobs.create!(status: :pending, progress: 0, total_steps: 5,
                                                 source_file: "%PDF-1.4", source_content_type: "application/pdf")

    without_credits do
      assert_raises(ClaudeUnavailableError) { RecipeImporter.new(job).perform_from_file }
    end

    job.reload
    assert job.failed?
    assert_equal "Recipe import service is currently unavailable. Please try again later.", job.error_message
    assert_match "Your credit balance is too low", job.error_detail
  end

  test "admins see the reason on the overview, with a banner while it's recent" do
    ReceiptScan.create!(household: households(:one), user: users(:one), week_of: Date.current, status: :failed,
                        error_message: ClaudeUnavailableError.user_message("Receipt upload"),
                        error_detail: "Claude API error 400 invalid_request_error: Your credit balance is too low")
    sign_in users(:three).tap { |user| user.update!(app_admin: true) }

    get admin_root_path

    assert_select "#admin_claude_outage", text: /Your credit balance is too low/
    assert_select "#admin_failures", text: /Receipt scan failed.*Your credit balance is too low/m
  end

  test "no banner without a recent Claude failure" do
    sign_in users(:three).tap { |user| user.update!(app_admin: true) }

    get admin_root_path
    assert_select "#admin_claude_outage", 0
  end
end
