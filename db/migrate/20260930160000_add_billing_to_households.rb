class AddBillingToHouseholds < ActiveRecord::Migration[8.1]
  def change
    change_table :households, bulk: true do |t|
      t.datetime :trial_ends_at
      t.string   :subscription_status, default: "trialing", null: false
      t.string   :plan_interval
      t.datetime :current_period_ends_at
      t.datetime :comped_until
      t.string   :trial_reminder_sent
      t.string   :stripe_customer_id
      t.string   :stripe_subscription_id
    end
    add_index :households, :stripe_customer_id, unique: true
    add_index :households, :stripe_subscription_id, unique: true
    add_index :households, [ :subscription_status, :trial_ends_at ]

    # Existing households start their free month now. bin/rails
    # billing:restart_trials resets it again on the day billing is switched on.
    reversible do |dir|
      dir.up { execute "UPDATE households SET trial_ends_at = #{connection.quote(30.days.from_now)}" }
    end
  end
end
