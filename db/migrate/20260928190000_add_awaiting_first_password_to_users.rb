class AddAwaitingFirstPasswordToUsers < ActiveRecord::Migration[8.1]
  def change
    # True for logins created by a household invite until the person sets
    # their own password — that first one shouldn't trigger the
    # "your password was changed" alert.
    add_column :users, :awaiting_first_password, :boolean, default: false, null: false
  end
end
