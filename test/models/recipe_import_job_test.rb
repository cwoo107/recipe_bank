require "test_helper"
require "rake"

class RecipeImportJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  def job(status:, updated_at:, **attributes)
    @user.recipe_import_jobs.create!(url: "https://example.com/r", status: status, **attributes).tap do |j|
      j.update_columns(updated_at: updated_at)
    end
  end

  test "stuck finds imports that stopped mid-run or were left unconfirmed" do
    killed_mid_run = job(status: :matching_ingredients, updated_at: 2.hours.ago)
    never_started  = job(status: :pending, updated_at: 3.days.ago)
    left_waiting   = job(status: :awaiting_confirmation, updated_at: 8.days.ago)
    legacy         = job(status: :completed, updated_at: 1.year.ago).tap { |j| j.update_columns(status: "7") }

    running_now    = job(status: :matching_ingredients, updated_at: 5.minutes.ago)
    still_deciding = job(status: :awaiting_confirmation, updated_at: 2.days.ago)
    done           = job(status: :completed, updated_at: 1.year.ago)
    failed         = job(status: :failed, updated_at: 1.year.ago)

    stuck = RecipeImportJob.stuck.to_a
    assert_equal [ killed_mid_run, never_started, left_waiting, legacy ].map(&:id).sort, (stuck.map(&:id) & [
      killed_mid_run, never_started, left_waiting, legacy, running_now, still_deciding, done, failed
    ].map(&:id)).sort
  end

  test "recipe_imports:clear_stuck deletes abandoned imports without running them, and completes ones that saved a recipe" do
    abandoned = job(status: :pending, updated_at: 3.days.ago)
    recipe    = Recipe.create!(title: "Saved anyway", servings: 2, user: @user)
    saved     = job(status: :failed, updated_at: 1.day.ago, recipe: recipe, error_message: "database is locked")
    running   = job(status: :matching_ingredients, updated_at: 1.minute.ago)

    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/recipe_imports.rake")

    RecipeImporter.stub(:new, ->(*) { flunk "stuck imports must not be run" }) do
      assert_output(/Dry run/) { Rake::Task["recipe_imports:clear_stuck"].execute }
      assert RecipeImportJob.exists?(abandoned.id)

      ENV["APPLY"] = "1"
      assert_output(/Applying/) { Rake::Task["recipe_imports:clear_stuck"].execute }
    ensure
      ENV.delete("APPLY")
    end

    assert_not RecipeImportJob.exists?(abandoned.id)
    assert saved.reload.completed?
    assert_nil saved.error_message
    assert RecipeImportJob.exists?(running.id)
  end
end
