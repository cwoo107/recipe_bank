class AddAppAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :app_admin, :boolean, default: false, null: false
  end
end
