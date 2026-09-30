require "test_helper"
require "minitest/mock"
require_relative "../support/fake_ollama_assistant"

class ProcessRecipeImportJobTest < ActiveJob::TestCase
  FakeExtractor = Struct.new(:data) do
    attr_reader :received
    def extract = data
  end

  SCRAPED = { title: "Photo Soup", description: "", servings: 2,
              ingredients: [ "1 cup water" ], steps: [ "Boil it." ] }.freeze

  setup do
    @user = users(:one)
  end

  test "the file stage reads the upload off the import, then clears it" do
    job = @user.recipe_import_jobs.create!(status: :pending, source_file: "%PDF fake", source_content_type: "application/pdf")
    seen = nil
    extractor = ->(io) { seen = [ io.read, io.content_type ]; FakeExtractor.new(SCRAPED) }

    RecipeFileExtractor.stub(:new, extractor) do
      OllamaAssistant.stub(:new, FakeOllamaAssistant.new) do
        ProcessRecipeImportJob.perform_now(job.id, "file")
      end
    end

    job.reload
    assert_equal [ "%PDF fake", "application/pdf" ], seen
    assert_nil job.source_file
    assert job.awaiting_confirmation?
  end

  test "a failed import isn't retried — the error is already on the import" do
    job = @user.recipe_import_jobs.create!(status: :pending, url: "https://example.com/r")
    scraper = Struct.new(:url) { def scrape = raise("Failed to fetch URL: 403 Forbidden") }

    RecipeScraper.stub(:new, ->(url) { scraper.new(url) }) do
      assert_nothing_raised { ProcessRecipeImportJob.perform_now(job.id, "url") }
    end

    assert job.reload.failed?
    assert_match(/403/, job.error_message)
    assert_no_enqueued_jobs only: ProcessRecipeImportJob
  end

  test "an import deleted before the worker gets to it is skipped" do
    assert_nothing_raised { ProcessRecipeImportJob.perform_now(-1, "url") }
  end

  test "a file import whose upload is gone fails with a clear message" do
    job = @user.recipe_import_jobs.create!(status: :pending, source_file: nil)

    ProcessRecipeImportJob.perform_now(job.id, "file")

    assert job.reload.failed?
    assert_match(/upload it again/, job.error_message)
  end
end
