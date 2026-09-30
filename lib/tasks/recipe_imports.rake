# lib/tasks/recipe_imports.rake
namespace :recipe_imports do
  # A recipe import cut off mid-run (a worker killed on deploy, or one from
  # before imports moved to Sidekiq, when every restart stranded any that
  # were running) is left stuck forever (RecipeImportJob.stuck). This
  # clears those out without running them — by now the user has likely
  # given up on them and added the recipe by hand.
  #
  # An import that did save its recipe (a stuck or "failed" job with a
  # recipe_id) isn't deleted: it's marked completed, since the recipe is
  # there.
  #
  #   bin/rails recipe_imports:clear_stuck            # show what would change
  #   bin/rails recipe_imports:clear_stuck APPLY=1    # do it
  desc "Delete abandoned recipe imports without running them; mark ones that saved a recipe completed (dry run unless APPLY=1)"
  task clear_stuck: :environment do
    apply = ENV['APPLY'] == '1'
    puts apply ? "Applying changes." : "Dry run — nothing will be changed. Re-run with APPLY=1 to apply."
    puts

    saved_but_not_completed = RecipeImportJob.where.not(recipe_id: nil).where.not(status: "completed").order(:id)
                                             .select(&:saved_recipe)
    stuck = RecipeImportJob.stuck.includes(:user).order(:id).to_a - saved_but_not_completed

    describe = lambda do |job|
      title = job.scraped_data.is_a?(Hash) ? job.scraped_data["title"] : nil
      raw    = job.read_attribute_before_type_cast(:status)
      status = job.status || (raw.nil? ? "never started" : "legacy status #{raw.inspect}")
      format("  #%-5d %-22s last touched %s  %s  %s", job.id, status,
             job.updated_at.strftime("%Y-%m-%d %H:%M"), job.user&.email.to_s, (title || job.url || "(file upload)").to_s.truncate(60))
    end

    puts "Saved a recipe but not marked completed → mark completed (#{saved_but_not_completed.size}):"
    saved_but_not_completed.each { |job| puts "#{describe.(job)}  → recipe ##{job.recipe_id}" }
    puts
    puts "Stuck or abandoned → delete without running (#{stuck.size}):"
    stuck.each { |job| puts describe.(job) }

    if apply
      RecipeImportJob.transaction do
        saved_but_not_completed.each do |job|
          job.update!(status: :completed, progress: 100, current_step: "Import completed!", error_message: nil)
        end
        stuck.each(&:destroy!)
      end
    end

    puts
    puts "Summary#{' (dry run — nothing changed)' unless apply}:"
    puts format("  %-28s %d", "marked completed", saved_but_not_completed.size)
    puts format("  %-28s %d", "deleted", stuck.size)
  end
end
