# The full error behind a failed receipt scan or recipe import, for admins
# (admin/users/show). error_message stays what the user is shown — for
# Claude being unavailable (out of credits, overloaded…) that's a plain
# "try again later" rather than the API's own message (ClaudeUnavailableError).
class AddErrorDetailToReceiptScansAndRecipeImportJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :receipt_scans, :error_detail, :text
    add_column :recipe_import_jobs, :error_detail, :text
  end
end
