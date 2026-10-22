require "test_helper"

# IngredientAssistant asks Claude Haiku (structured outputs) and falls back
# to its offline guesses whenever there's no usable answer. A stand-in client
# plays the API so nothing leaves the machine.
class IngredientAssistantTest < ActiveSupport::TestCase
  Block    = Struct.new(:type, :text, keyword_init: true)
  Details  = Struct.new(:category, keyword_init: true)
  Response = Struct.new(:stop_reason, :stop_details, :content, keyword_init: true)

  # Records each request and answers with whatever the test hands it (a
  # Response, or an error to raise).
  class FakeClient
    attr_reader :requests

    def initialize(answer)
      @answer   = answer
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      raise @answer if @answer.is_a?(Exception)

      @answer
    end
  end

  def answer(items, stop_reason: :end_turn)
    Response.new(stop_reason:, stop_details: nil,
                 content: [ Block.new(type: :thinking, text: nil), Block.new(type: :text, text: { items: }.to_json) ])
  end

  INGREDIENTS = [ { name: "Basil" }, { name: "Frozen peas" } ].freeze

  test "asks Claude Haiku for a schema-shaped answer and returns its items" do
    client = FakeClient.new(answer([ { name: "Basil", family: "produce" }, { name: "Frozen peas", family: "frozen" } ]))

    result = IngredientAssistant.new(provider: "claude", client:).classify_ingredient_families(INGREDIENTS)

    assert_equal [ { "name" => "Basil", "family" => "produce" }, { "name" => "Frozen peas", "family" => "frozen" } ], result
    request = client.requests.first
    assert_equal "claude-haiku-5-5", request[:model]
    assert_equal :low, request.dig(:output_config, :effort)
    assert_equal :json_schema, request.dig(:output_config, :format_, :type)
    assert_equal Ingredient::FAMILIES.keys,
                 request.dig(:output_config, :format_, :schema, :properties, :items, :items, :properties, :family, :enum)
    assert_nil request[:temperature], "Haiku 5.5 rejects non-default sampling"
  end

  test "a refusal falls back to the offline guesses" do
    refusal = Response.new(stop_reason: :refusal, stop_details: Details.new(category: :cyber), content: [])

    result = IngredientAssistant.new(provider: "claude", client: FakeClient.new(refusal)).classify_ingredient_families(INGREDIENTS)

    assert_equal [ "produce", "frozen" ], result.map { |row| row["family"] }
  end

  test "a reply cut short falls back too" do
    result = IngredientAssistant.new(provider: "claude", client: FakeClient.new(answer([], stop_reason: :max_tokens)))
                                .estimate_nutrition_facts([ { name: "Olive oil", family: "fat" } ])

    assert_equal 120, result.first[:calories] # the fat family's fallback estimate
  end

  test "an unreadable answer falls back" do
    garbled = Response.new(stop_reason: :end_turn, stop_details: nil, content: [ Block.new(type: :text, text: "not json") ])

    result = IngredientAssistant.new(provider: "claude", client: FakeClient.new(garbled)).resolve_ingredients(
      [ { ingredient: { original: "2 cups rice", name: "rice", quantity: 2, unit: "cup" }, candidates: [] } ]
    )

    assert_equal "create", result.first["action"]
  end

  test "an outage falls back instead of failing the import" do
    outage = Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"))

    result = IngredientAssistant.new(provider: "claude", client: FakeClient.new(outage)).classify_ingredient_families(INGREDIENTS)

    assert_equal [ "produce", "frozen" ], result.map { |row| row["family"] }
  end

  test "without an API key it doesn't call out at all" do
    previous = ENV.delete("ANTHROPIC_API_KEY")

    result = IngredientAssistant.new(provider: "claude").classify_ingredient_families(INGREDIENTS)

    assert_equal [ "produce", "frozen" ], result.map { |row| row["family"] }
  ensure
    ENV["ANTHROPIC_API_KEY"] = previous if previous
  end

  # ── Ollama (the default — what runs on Railway) ──

  OllamaReply = Struct.new(:code, :body, keyword_init: true) do
    def success? = code == 200
  end

  def ollama_reply(json) = OllamaReply.new(code: 200, body: { response: json }.to_json)

  test "Ollama is the provider unless INGREDIENT_AI says claude" do
    assert_equal "ollama", IngredientAssistant.new(provider: nil).provider
    assert_equal "ollama", IngredientAssistant.new(provider: "something-else").provider
    assert_equal "claude", IngredientAssistant.new(provider: "claude").provider
  end

  test "Ollama gets the original JSON-mode request and prompt wording" do
    sent = nil
    reply = ollama_reply([ { name: "Basil", family: "produce" }, { name: "Frozen peas", family: "frozen" } ].to_json)
    result = HTTParty.stub(:post, ->(url, options) { sent = [ url, JSON.parse(options[:body]), options[:timeout] ]; reply }) do
      IngredientAssistant.new(provider: "ollama").classify_ingredient_families(INGREDIENTS)
    end

    assert_equal [ "produce", "frozen" ], result.map { |row| row["family"] }
    url, body, timeout = sent
    assert_match %r{/api/generate\z}, url
    assert_equal [ "llama2", false, "json" ], body.values_at("model", "stream", "format")
    assert_includes body["prompt"], "Respond with ONLY valid JSON array (no markdown, no explanation):"
    assert_equal 120, timeout
  end

  test "Ollama's JSON can come wrapped in an object" do
    reply = ollama_reply({ items: [ { name: "Basil", family: "produce" } ] }.to_json)
    result = HTTParty.stub(:post, reply) do
      IngredientAssistant.new(provider: "ollama").classify_ingredient_families([ { name: "Basil" } ])
    end

    assert_equal [ "produce" ], result.map { |row| row["family"] }
  end

  test "Ollama being down falls back" do
    result = HTTParty.stub(:post, ->(*) { raise Errno::ECONNREFUSED }) do
      IngredientAssistant.new(provider: "ollama").estimate_nutrition_facts([ { name: "Olive oil", family: "fat" } ])
    end

    assert_equal 120, result.first[:calories]
  end
end
