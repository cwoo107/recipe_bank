require "test_helper"

class PurgeStaleUploadsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @household = households(:one)
  end

  test "an upload nobody read within the hour is cleared and its import or scan failed" do
    import = @user.recipe_import_jobs.create!(status: :pending, source_file: "%PDF", source_content_type: "application/pdf",
                                              created_at: 2.hours.ago)
    scan = @household.receipt_scans.create!(user: @user, week_of: Date.current.beginning_of_week, source_file: "jpeg",
                                            source_content_type: "image/jpeg", created_at: 2.hours.ago)

    PurgeStaleUploadsJob.perform_now

    assert_nil import.reload.source_file
    assert import.failed?
    assert_match "expired", import.error_message
    assert_nil scan.reload.source_file
    assert scan.failed?
  end

  test "a fresh upload still waiting on the worker is left alone" do
    import = @user.recipe_import_jobs.create!(status: :pending, source_file: "%PDF", source_content_type: "application/pdf")

    PurgeStaleUploadsJob.perform_now

    assert_equal "%PDF", import.reload.source_file
    assert import.pending?
  end
end
