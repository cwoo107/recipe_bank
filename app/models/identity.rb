# A Google or Apple account the user signs in with (User::SocialSignIn).
# provider is OmniAuth's name for it; uid is that provider's stable id for
# the person — never the email, which can change.
class Identity < ApplicationRecord
  PROVIDERS = %w[google_oauth2 apple].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
