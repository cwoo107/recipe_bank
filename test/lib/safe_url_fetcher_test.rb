require "test_helper"
require_relative "../support/fake_network"

# None of these reach the network: each is refused before connecting, or
# answered by FakeNetwork.
class SafeUrlFetcherTest < ActiveSupport::TestCase
  include FakeNetwork

  def assert_refused(url, message)
    error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new(url).fetch }
    assert_equal message, error.message
  end

  test "refuses bare paths and non-web schemes" do
    ["/etc/hosts", "file:///etc/hosts", "ftp://example.com/r", "|echo hi", "not a url", ""].each do |url|
      assert_refused url, SafeUrlFetcher::NOT_A_LINK
    end
  end

  test "refuses loopback, private, link-local and metadata addresses" do
    %w[
      http://127.0.0.1/ http://localhost:3000/ http://10.0.0.5/ http://192.168.1.1/
      http://172.16.0.1/ http://169.254.169.254/latest/meta-data http://100.64.0.1/
      http://0.0.0.0/ http://[::1]/ http://[::ffff:127.0.0.1]/ http://[fd12::1]/
    ].each do |url|
      assert_refused url, SafeUrlFetcher::NOT_ALLOWED
    end
  end

  test "returns the body and the charset from the Content-Type header" do
    ok = http_response(200, body: "<html>hi</html>")
    ok["content-type"] = "text/html; charset=ISO-8859-1"

    with_fake_network(ok) do |http|
      assert_equal [ "<html>hi</html>", "ISO-8859-1" ], SafeUrlFetcher.new("https://example.com/r").fetch
      assert_equal FakeNetwork::PUBLIC_ADDRESS, http.ipaddr, "connects to the address it checked"
    end
  end

  test "a redirect to an internal address is refused" do
    with_fake_network(http_response(302, location: "http://127.0.0.1/admin")) do
      error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new("https://example.com/r").fetch }
      assert_equal :not_allowed, error.reason
    end
  end

  test "gives up after too many redirects" do
    loops = Array.new(SafeUrlFetcher::MAX_REDIRECTS + 1) { http_response(302, location: "/again") }
    with_fake_network(*loops) do
      error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new("https://example.com/r").fetch }
      assert_equal :too_many_redirects, error.reason
    end
  end

  test "an error response carries its status" do
    with_fake_network(http_response(404)) do
      error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new("https://example.com/r").fetch }
      assert_equal [ :http_status, 404 ], [ error.reason, error.status ]
    end
  end

  test "a page over the size cap is refused" do
    with_fake_network(http_response(200, body: "x" * 11)) do
      error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new("https://example.com/r", max_bytes: 10).fetch }
      assert_equal :too_large, error.reason
    end
  end

  test "network failures are reworded, not passed through" do
    { Net::OpenTimeout.new => :timeout, Errno::ECONNREFUSED.new => :refused,
      SocketError.new("getaddrinfo") => :not_found, EOFError.new => :unreachable }.each do |raised, reason|
      with_fake_network(raised) do
        error = assert_raises(SafeUrlFetcher::Error) { SafeUrlFetcher.new("https://example.com/r").fetch }
        assert_equal reason, error.reason
        assert_no_match(/getaddrinfo|Errno|EOF/, error.message)
      end
    end
  end

  test "public addresses aren't blocked" do
    refute SafeUrlFetcher.blocked_address?("93.184.215.14")
    refute SafeUrlFetcher.blocked_address?("2606:2800:21f:cb07:6820:80da:af6b:8b2c")
  end
end
