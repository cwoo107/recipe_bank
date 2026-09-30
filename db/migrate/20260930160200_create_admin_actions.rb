class CreateAdminActions < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_actions do |t|
      t.references :admin,     null: false, foreign_key: { to_table: :users }
      t.references :household, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.json   :details, default: {}, null: false
      t.text   :note
      t.timestamps
    end
  end
end
