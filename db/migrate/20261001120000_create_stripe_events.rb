# Stripe events already handled (StripeEventJob), so a redelivered webhook —
# Stripe retries until it gets a 2xx — doesn't send a second email.
class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :event_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.timestamps
    end
  end
end
