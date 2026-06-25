class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.string :title
      t.belongs_to :user, null: false, foreign_key: true
      t.boolean :public

      t.timestamps
    end
  end
end
