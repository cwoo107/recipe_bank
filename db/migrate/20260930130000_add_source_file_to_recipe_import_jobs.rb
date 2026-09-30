# File imports (a photo or PDF of a recipe) now run on Sidekiq instead of a
# thread in the web request, so the uploaded bytes have to be somewhere the
# worker can read them. They're kept on the import itself only until the
# worker has extracted the recipe (RecipeImporter#perform_from_file clears
# them), which also works when the worker runs in a different container.
class AddSourceFileToRecipeImportJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :recipe_import_jobs, :source_file, :binary
    add_column :recipe_import_jobs, :source_content_type, :string
  end
end
