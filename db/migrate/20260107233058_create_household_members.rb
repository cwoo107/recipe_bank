class CreateHouseholdMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :household_members do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name
      t.boolean :child

      t.timestamps
    end
  end
end
