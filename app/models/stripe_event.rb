# A Stripe webhook event that's been handled (see StripeEventJob).
class StripeEvent < ApplicationRecord
  validates :event_id, :event_type, presence: true
end
