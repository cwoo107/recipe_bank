class CreateChoreTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :chore_tasks do |t|
      t.references :chore, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :chore_tasks, [ :chore_id, :position ]
  end
end
