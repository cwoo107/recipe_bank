require "minitest/mock"

# Stands in for the network under SafeUrlFetcher: every host name resolves
# to a public address (an IP address to itself, as it really does), and each
# request gets the next of `responses` — a Net::HTTPResponse, or an
# exception to raise.
module FakeNetwork
  PUBLIC_ADDRESS = "93.184.215.14".freeze

  class FakeHttp
    attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests  = []
    end

    def start = yield

    def request(req)
      @requests << req
      response = @responses.shift or raise "FakeNetwork: no response left for #{req.path}"
      raise response if response.is_a?(Exception)
      yield response
    end
  end

  # Yields the fake, so a test can look at the requests it was sent.
  def with_fake_network(*responses)
    http = FakeHttp.new(responses)
    resolve = ->(host) { host.match?(Resolv::AddressRegex) ? [ host ] : [ PUBLIC_ADDRESS ] }
    Resolv.stub(:getaddresses, resolve) do
      Net::HTTP.stub(:new, http) { yield http }
    end
  end

  def http_response(code, body: "", location: nil)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s).new("1.1", code.to_s, "")
    response["location"] = location if location
    response.define_singleton_method(:read_body) { |&block| block.call(body) }
    response
  end
end
