# Claude couldn't be used for a request: out of API credits, a bad key, rate
# limited, overloaded, timed out or unreachable. Nothing the user can fix,
# so they're told the feature is unavailable (user_message) while the full
# error — this one's message — is kept for admins (error_detail on the scan
# or import). Raised by ReceiptExtractor and RecipeFileExtractor.
class ClaudeUnavailableError < StandardError
  # service: what the user was doing, as they'd name it ("Receipt upload").
  def self.user_message(service)
    "#{service} service is currently unavailable. Please try again later."
  end

  # Wraps an Anthropic SDK error. Leads with the API's own explanation ("Your
  # credit balance is too low…") — the SDK's message starts with the request
  # URL and body dump, which pushes it out of sight on the admin page.
  def self.from(error)
    body   = error.body.is_a?(Hash) ? error.body.with_indifferent_access : {}
    reason = body.dig(:error, :message).presence || error.message
    kind   = body.dig(:error, :type)
    request_id = body[:request_id].presence || error.request_id

    new([ "Claude API error #{error.status || "(no response)"}#{" #{kind}" if kind}: #{reason}",
          ("request #{request_id}" if request_id) ].compact.join(" · "))
  end
end
