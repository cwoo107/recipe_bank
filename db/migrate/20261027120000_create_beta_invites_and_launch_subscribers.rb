# Pre-launch: sign-ups are closed except through a beta invite link an app
# admin hands out, and anyone can join the launch mailing list.
class CreateBetaInvitesAndLaunchSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :beta_invites do |t|
      t.string :token, null: false
      t.string :name                       # who it's for — just for the admin's list
      t.references :created_by,  foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :redeemed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :redeemed_at
      t.timestamps
    end
    add_index :beta_invites, :token, unique: true

    create_table :launch_subscribers do |t|
      t.string :email, null: false
      t.string :unsubscribe_token, null: false
      t.datetime :unsubscribed_at
      t.timestamps
    end
    add_index :launch_subscribers, :email, unique: true
    add_index :launch_subscribers, :unsubscribe_token, unique: true
  end
end
