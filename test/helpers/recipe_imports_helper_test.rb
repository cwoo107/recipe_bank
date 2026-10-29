require "test_helper"

class RecipeImportsHelperTest < ActionView::TestCase
  STEPS = %i[fetching_html parsing_recipe matching_ingredients awaiting_confirmation resolving_with_ai creating_recipe].freeze

  # Each step's icon colour, which says its state: olive (done or running),
  # dusty rose (failed) or gray (pending).
  def step_states(job)
    STEPS.to_h do |step|
      html = render_import_step(job, step, step.to_s.humanize, "Done")
      state = if html.include?("bg-dusty-rose-500") then :failed
              elsif html.include?("animate-spin") then :current
              elsif html.include?("bg-[#5f734c]") then :done
              else :pending
              end
      [ step, state ]
    end
  end

  test "a failed import marks the step it failed on and leaves the rest pending" do
    job = RecipeImportJob.new(status: :failed, failed_step: "fetching_html")

    assert_equal({ fetching_html: :failed, parsing_recipe: :pending, matching_ingredients: :pending,
                   awaiting_confirmation: :pending, resolving_with_ai: :pending, creating_recipe: :pending },
                 step_states(job))
  end

  test "the reason it failed sits under the failed step, not the others" do
    job = RecipeImportJob.new(status: :failed, failed_step: "fetching_html", error_message: "This site blocks apps.")

    assert_includes render_import_step(job, :fetching_html, "Fetching HTML", "Downloaded"), "This site blocks apps."
    assert_not_includes render_import_step(job, :parsing_recipe, "Parsing Recipe", "Parsed"), "This site blocks apps."
  end

  test "steps before the failed one show as done" do
    job = RecipeImportJob.new(status: :failed, failed_step: "resolving_with_ai")
    states = step_states(job)

    assert_equal %i[done done done done failed pending], states.values
  end

  test "a failed import with no recorded step shows nothing as done" do
    job = RecipeImportJob.new(status: :failed, failed_step: nil)

    assert_equal [ :pending ], step_states(job).values.uniq
  end

  test "a running import is unchanged: done, then running, then pending" do
    job = RecipeImportJob.new(status: :matching_ingredients)

    assert_equal %i[done done current pending pending pending], step_states(job).values
  end
end
