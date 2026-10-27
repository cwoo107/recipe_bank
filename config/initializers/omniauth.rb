# Sign in with Google / Apple — the providers themselves are set up in
# devise.rb (config.omniauth). A provider's buttons only show once its keys
# are in the environment, so dev and test run fine without them.
module SocialSignIn
  PROVIDERS = {
    "google_oauth2" => { name: "Google", keys: %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET] },
    "apple"         => { name: "Apple",  keys: %w[APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY] }
  }.freeze

  def self.enabled?(provider)
    PROVIDERS.fetch(provider.to_s)[:keys].all? { |key| ENV[key].present? }
  end

  def self.enabled_providers
    PROVIDERS.keys.select { |provider| enabled?(provider) }
  end

  def self.name_for(provider)
    PROVIDERS.fetch(provider.to_s)[:name]
  end

  # Apple returns from sign-in by POSTing a form from appleid.apple.com. The
  # browser won't send our SameSite=Lax session cookie with that cross-site
  # POST, so OmniAuth would find no state (or nonce) to check it against and
  # reject the sign-in. Bouncing it to a GET of the same URL — a top-level
  # navigation, which does carry the cookie — lets the callback run normally.
  class AppleFormPost
    CALLBACK_PATH = "/users/auth/apple/callback"

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.post? && request.path == CALLBACK_PATH

      [ 303, { "location" => "#{CALLBACK_PATH}?#{Rack::Utils.build_query(request.POST)}" }, [] ]
    end
  end
end

# devise_for sets this too, but only once the routes load — which Rails does
# lazily, so until some request loaded them, sign-in buttons would 404.
OmniAuth.config.path_prefix = "/users/auth"

# Ahead of Warden — Devise adds the OmniAuth strategies after it.
Rails.application.config.middleware.insert_before Warden::Manager, SocialSignIn::AppleFormPost
