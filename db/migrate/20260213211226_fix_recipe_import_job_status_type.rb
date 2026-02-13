class FixRecipeImportJobStatusType < ActiveRecord::Migration[8.1]
  def change
    # If status is currently an integer, change it to string
    change_column :recipe_import_jobs, :status, :string, default: 'pending', null: false

    # Add default values if missing
    change_column_default :recipe_import_jobs, :progress, from: nil, to: 0
    change_column_default :recipe_import_jobs, :total_steps, from: nil, to: 5
  end
end
