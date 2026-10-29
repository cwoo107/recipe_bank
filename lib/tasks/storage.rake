# lib/tasks/storage.rake
namespace :storage do
  # Steps used to take file and image attachments (stored with Active
  # Storage on local disk). They're text only now, and Active Storage's
  # routes aren't mounted, so any attachment saved before then is never
  # shown. This takes them out of the steps they're in and deletes every
  # stored file — nothing else in the app uses Active Storage.
  #
  #   bin/rails storage:purge_step_attachments            # show what would change
  #   bin/rails storage:purge_step_attachments APPLY=1    # do it
  desc "Strip attachments out of recipe steps and delete every Active Storage file (dry run unless APPLY=1)"
  task purge_step_attachments: :environment do
    apply = ENV['APPLY'] == '1'
    puts apply ? "Applying changes." : "Dry run — nothing will be changed. Re-run with APPLY=1 to apply."
    puts

    steps = Step.joins(:rich_text_content)
                .where("action_text_rich_texts.body LIKE ? OR action_text_rich_texts.body LIKE ? OR action_text_rich_texts.body LIKE ?",
                       "%<action-text-attachment%", "%<img%", "%<figure%")
                .order(:id).to_a
    blobs = ActiveStorage::Blob.order(:id).to_a

    puts "Steps with attachments → strip them (#{steps.size}):"
    steps.each { |step| puts format("  step #%-6d recipe #%d", step.id, step.recipe_id) }
    puts
    puts "Stored files → delete (#{blobs.size}):"
    blobs.each { |blob| puts format("  blob #%-6d %-40s %s", blob.id, blob.filename.to_s.truncate(40), ActiveSupport::NumberHelper.number_to_human_size(blob.byte_size)) }

    if apply
      # Saving runs Step#remove_attachments.
      steps.each(&:save!)
      ActiveStorage::Attachment.find_each(&:purge)
      ActiveStorage::Blob.find_each(&:purge)
    end

    puts
    puts "Summary#{' (dry run — nothing changed)' unless apply}:"
    puts format("  %-28s %d", "steps stripped", steps.size)
    puts format("  %-28s %d", "files deleted", blobs.size)
  end
end
