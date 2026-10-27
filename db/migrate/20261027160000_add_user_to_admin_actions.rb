# The account an admin action was about (e.g. who they viewed the app as),
# for the admin user page's history. No foreign key, like household_id —
# the record outlives the user.
class AddUserToAdminActions < ActiveRecord::Migration[8.1]
  def change
    add_reference :admin_actions, :user, index: true
  end
end
