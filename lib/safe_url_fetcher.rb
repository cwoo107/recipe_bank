require 'net/http'
require 'ipaddr'
require 'resolv'

# Fetches a URL a user typed in, from the server — so it has to refuse
# anything that isn't a public web page: other schemes and bare paths (which
# URI.open would have read off our own disk), and hosts that resolve to
# loopback, private, link-local or other internal addresses (Railway's
# private network, cloud metadata). The connection goes to the address we
# checked rather than re-resolving, and every redirect is checked again.
#
# Errors are raised as SafeUrlFetcher::Error with a message fit to show the
# user — never the underlying exception's, which can describe our network.
# Callers with their own wording (CalendarSyncJob) go by its #reason and,
# for an error response, its #status.
class SafeUrlFetcher
  class Error < StandardError
    REASONS = %i[not_a_link not_allowed not_found timeout refused ssl unreachable
                 too_large http_status bad_redirect too_many_redirects].freeze

    attr_reader :reason, :status

    def initialize(message, reason:, status: nil)
      raise ArgumentError, "unknown reason #{reason.inspect}" unless REASONS.include?(reason)
      super(message)
      @reason = reason
      @status = status
    end
  end

  MAX_REDIRECTS = 5
  MAX_BYTES     = 5.megabytes
  OPEN_TIMEOUT  = 5
  READ_TIMEOUT  = 15

  # A current desktop browser; sites behind bot protection turn away a bare
  # "Mozilla/5.0".
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' \
               '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
    203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 64:ff9b::/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  NOT_A_LINK = "That doesn't look like a web address — paste the full link, starting with https://."
  NOT_ALLOWED = "That address can't be imported from — use a link to a public web page."

  def self.blocked_address?(ip)
    ip = IPAddr.new(ip.to_s)
    ip = ip.native # ::ffff:127.0.0.1 is 127.0.0.1
    BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def initialize(url, user_agent: USER_AGENT, accept: 'text/html,application/xhtml+xml',
                 max_bytes: MAX_BYTES, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    @url          = url.to_s.strip
    @user_agent   = user_agent
    @accept       = accept
    @max_bytes    = max_bytes
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  # Returns [body, charset] — charset from the Content-Type header, or nil.
  def fetch
    uri = parse(@url)

    (MAX_REDIRECTS + 1).times do
      response, body = request(uri)

      case response
      when Net::HTTPSuccess
        return [body, response.type_params['charset']]
      when Net::HTTPRedirection
        location = response['location']
        raise Error.new("The site sent a redirect with nowhere to go.", reason: :bad_redirect) if location.blank?
        uri = parse(URI.join(uri.to_s, location).to_s)
      else
        raise Error.new("The site responded with an error (#{response.code}). Check the link, or try again later.",
                        reason: :http_status, status: response.code.to_i)
      end
    end

    raise Error.new("The site redirected too many times.", reason: :too_many_redirects)
  end

  private

  def parse(url)
    uri = URI.parse(url)
    raise Error.new(NOT_A_LINK, reason: :not_a_link) unless uri.is_a?(URI::HTTP) && uri.host.present?
    uri
  rescue URI::InvalidURIError
    raise Error.new(NOT_A_LINK, reason: :not_a_link)
  end

  # Every address the host resolves to must be public — otherwise a host with
  # one public and one internal record could be pointed at either.
  def resolve(host)
    host = host.delete_prefix('[').delete_suffix(']')
    addresses = Resolv.getaddresses(host)
    raise Error.new("That website couldn't be found. Check the link for typos.", reason: :not_found) if addresses.empty?
    raise Error.new(NOT_ALLOWED, reason: :not_allowed) if addresses.any? { |ip| self.class.blocked_address?(ip) }
    addresses.first
  end

  def request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr       = resolve(uri.host)
    http.use_ssl      = uri.scheme == 'https'
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout

    http.start do
      get = Net::HTTP::Get.new(uri.request_uri, 'User-Agent' => @user_agent, 'Accept' => @accept)
      http.request(get) do |response|
        return [response, nil] unless response.is_a?(Net::HTTPSuccess)
        return [response, read_capped(response)]
      end
    end
  rescue Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error.new("The site took too long to respond. Try again in a little while.", reason: :timeout)
  rescue OpenSSL::SSL::SSLError
    raise Error.new("A secure connection to the site couldn't be made.", reason: :ssl)
  rescue Errno::ECONNREFUSED
    raise Error.new("The site turned the connection away. Try again later.", reason: :refused)
  rescue SocketError
    raise Error.new("That website couldn't be found. Check the link for typos.", reason: :not_found)
  rescue SystemCallError, IOError, Net::HTTPBadResponse, EOFError
    raise Error.new("Couldn't reach that site. Check the link, or try again later.", reason: :unreachable)
  end

  def read_capped(response)
    body = +''
    response.read_body do |chunk|
      body << chunk
      raise Error.new("That page is too large to import.", reason: :too_large) if body.bytesize > @max_bytes
    end
    body
  end
end
