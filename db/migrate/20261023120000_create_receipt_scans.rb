class CreateReceiptScans < ActiveRecord::Migration[8.1]
  def change
    create_table :receipt_scans do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :week_of, null: false
      t.string :status, null: false, default: "pending"
      t.binary :source_file
      t.string :source_content_type
      t.string :store_name
      t.json :items
      t.text :error_message
      t.timestamps
    end
  end
end
