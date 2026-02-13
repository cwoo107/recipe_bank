class CreateRecipeImportJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_import_jobs do |t|
      t.string :url
      t.string :status
      t.string :current_step
      t.integer :progress
      t.integer :total_steps
      t.integer :recipe_id
      t.text :error_message
      t.json :scraped_data
      t.json :matched_ingredients

      t.timestamps
    end
  end
end
