class CreateTodos < ActiveRecord::Migration[8.1]
  def change
    create_table :todos do |t|
      t.string  :title,       null: false
      t.text    :description
      t.integer :priority,    null: false                  # 1=Low, 2=Medium, 3=High, 4=Urgent
      t.string  :status,      null: false, default: "todo" # todo | in_progress | done
      t.integer :position,    null: false, default: 0
      t.integer :user_id,     null: false

      t.timestamps
    end

    add_index :todos, :user_id
    add_index :todos, [ :user_id, :status ]
    add_index :todos, [ :user_id, :status, :position ]
    add_foreign_key :todos, :users
  end
end