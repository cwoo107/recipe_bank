# Launch-list households' three free months, and the referral program.
#
# launch_offer: the household's owner was on the launch list, so its first
# annual payment is three months less (StripeBilling::LAUNCH_COUPON) — cleared
# once used. Backfilled from the list for households that exist.
#
# referral_code: the household's share link (/r/:code). free_months_banked:
# referral rewards waiting for a subscription to go on (StripeBilling).
#
# referrals: one row per household that signed up through someone's link —
# the referrer earns three free months once that household's first annual
# payment is past the refund window (ReferralRewardsJob).
class AddLaunchOfferAndReferrals < ActiveRecord::Migration[8.1]
  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  def up
    add_column :households, :launch_offer, :boolean, default: false, null: false
    add_column :households, :referral_code, :string
    add_column :households, :free_months_banked, :integer, default: 0, null: false
    add_index :households, :referral_code, unique: true

    create_table :referrals do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :households }
      t.references :referred, null: false, foreign_key: { to_table: :households }, index: { unique: true }
      t.string :stripe_invoice_id
      t.datetime :paid_at
      t.datetime :qualifies_at
      t.datetime :rewarded_at
      t.datetime :voided_at
      t.timestamps
    end
    add_index :referrals, :qualifies_at

    MigrationHousehold.reset_column_information
    listed = select_values("SELECT email FROM launch_subscribers").to_set
    MigrationHousehold.find_each do |household|
      owner_email = select_value("SELECT email FROM users WHERE id = #{household.owner_id.to_i}")
      household.update_columns(
        referral_code: SecureRandom.alphanumeric(8).downcase,
        launch_offer: listed.include?(owner_email.to_s.strip.downcase)
      )
    end
  end

  def down
    drop_table :referrals
    remove_index :households, :referral_code
    remove_column :households, :free_months_banked
    remove_column :households, :referral_code
    remove_column :households, :launch_offer
  end
end
