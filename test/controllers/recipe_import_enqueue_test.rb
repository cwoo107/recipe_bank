require "test_helper"

# Starting an import hands the work to Sidekiq (ProcessRecipeImportJob)
# rather than running it on a thread in the web process.
class RecipeImportEnqueueTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in users(:one)
  end

  test "importing from a URL enqueues the import" do
    assert_enqueued_jobs 1, only: ProcessRecipeImportJob do
      post recipe_imports_url, params: { url: "https://example.com/soup" }
    end

    job = RecipeImportJob.last
    assert_enqueued_with(job: ProcessRecipeImportJob, args: [ job.id, "url" ])
    assert job.pending?
  end

  test "importing from a file keeps the upload on the import for the worker, and enqueues it" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 fake"), "application/pdf", original_filename: "soup.pdf")

    post create_from_file_recipe_imports_url, params: { file: upload }

    job = RecipeImportJob.last
    assert_equal "%PDF-1.4 fake", job.source_file
    assert_equal "application/pdf", job.source_content_type
    assert_enqueued_with(job: ProcessRecipeImportJob, args: [ job.id, "file" ])
  end

  test "an oversized upload is turned away before anything is stored" do
    with_max_upload_size(10) do
      upload = Rack::Test::UploadedFile.new(StringIO.new("x" * 11), "application/pdf", original_filename: "huge.pdf")

      assert_no_difference("RecipeImportJob.count") do
        post create_from_file_recipe_imports_url, params: { file: upload }
      end
    end

    assert_redirected_to new_recipe_import_path
    assert_no_enqueued_jobs only: ProcessRecipeImportJob
  end

  private

  # Lowers the upload cap for one test, rather than building a 25 MB file.
  def with_max_upload_size(bytes)
    original = RecipeImportsController::MAX_UPLOAD_SIZE
    RecipeImportsController.send(:remove_const, :MAX_UPLOAD_SIZE)
    RecipeImportsController.const_set(:MAX_UPLOAD_SIZE, bytes)
    yield
  ensure
    RecipeImportsController.send(:remove_const, :MAX_UPLOAD_SIZE)
    RecipeImportsController.const_set(:MAX_UPLOAD_SIZE, original)
  end
end
