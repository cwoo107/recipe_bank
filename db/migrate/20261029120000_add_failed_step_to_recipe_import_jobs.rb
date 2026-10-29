# The step an import was on when it failed (RecipeImporter), so the progress
# list can mark that step with an X and leave the later ones pending — once
# status is "failed" there's nothing else saying how far it got.
class AddFailedStepToRecipeImportJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :recipe_import_jobs, :failed_step, :string
  end
end
