# app/models/receipt_extractor.rb
#
# Reads a grocery receipt photo (or PDF) with Claude Haiku and, in the same
# pass, matches each line to one of the household's ingredients — receipt
# abbreviations ("KS ORG LG EGGS 24CT") are beyond what fuzzy matching on
# names can place, but not beyond the model. Answers come back in
# RECEIPT_SCHEMA (structured outputs).
class ReceiptExtractor
  include ClaudeFileContent

  MODEL = 'claude-haiku-5-5'

  # The household's ingredients go into the prompt for matching; past this
  # many, the ones on recent grocery lists are sent first (see ReceiptScanner).
  MAX_CANDIDATES = 1_000

  NULLABLE_NUMBER = { anyOf: [ { type: 'number' }, { type: 'null' } ] }.freeze

  RECEIPT_SCHEMA = {
    type: 'object',
    properties: {
      store_name: { anyOf: [ { type: 'string' }, { type: 'null' } ] },
      items: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            text:          { type: 'string' },
            name:          { type: 'string' },
            quantity:      NULLABLE_NUMBER,
            unit_price:    NULLABLE_NUMBER,
            total_price:   NULLABLE_NUMBER,
            by_weight:     { type: 'boolean' },
            ingredient_id: { anyOf: [ { type: 'integer' }, { type: 'null' } ] }
          },
          required: %w[text name quantity unit_price total_price by_weight ingredient_id],
          additionalProperties: false
        }
      }
    },
    required: %w[store_name items],
    additionalProperties: false
  }.freeze

  # candidates: [{ id:, name: }] — the ingredients a line may be matched to.
  def initialize(file, candidates: [])
    @file = file
    @content_type = file.content_type
    @candidates = candidates
  end

  def extract
    raise "Unsupported file type: #{@content_type}" unless SUPPORTED_TYPES.include?(@content_type)

    parse_response(call_claude)
  end

  private

  # The JSON text of Claude's answer. Raises (the scan shows it as failed)
  # when there isn't one — an API error, a refusal, or a reply cut short.
  def call_claude
    response = Anthropic::Client.new(timeout: 120).messages.create(
      model:         MODEL,
      max_tokens:    16_000,
      output_config: { effort: :medium, format_: { type: :json_schema, schema: RECEIPT_SCHEMA } },
      messages:      [
        {
          role:    'user',
          content: [
            file_content_block,
            { type: 'text', text: extraction_prompt }
          ]
        }
      ]
    )

    unless response.stop_reason == :end_turn
      raise "Claude couldn't read the receipt (stop_reason #{response.stop_reason}#{" — #{response.stop_details&.category}" if response.stop_reason == :refusal})"
    end

    # The answer is the text block — Haiku can put thinking blocks first.
    response.content.find { |block| block.type == :text }&.text
  rescue Anthropic::Errors::APIStatusError => e
    raise "Claude API error: #{e.status} — #{e.message}"
  end

  def extraction_prompt
    <<~PROMPT
      This is a photo of a grocery store receipt. List every purchased item on it.

      Rules:
      - text: the line exactly as printed (e.g. "KS ORG LG EGGS 24CT")
      - name: what the item is in plain words (e.g. "organic large eggs")
      - quantity: how many were bought (1 if the receipt doesn't say); for items
        sold by weight, the weight
      - unit_price: the price of one item (or per weight unit when sold by weight)
        after any discount or coupon printed for that line
      - total_price: what the line cost in all, after any discount or coupon
      - by_weight: true when the item is priced by weight (e.g. "2.31 lb @ $0.59/lb")
      - ingredient_id: the id of the ingredient below that this item is, or null
        when none of them is a good match. Only match when it's the same thing
        (a brand or size difference is fine; "milk" is not "almond milk").
      - Leave out tax, subtotals, totals, payment, change, bag fees, deposits,
        and coupon or discount lines (fold those into the item they apply to).

      Ingredients (id: name):
      #{@candidates.map { |c| "#{c[:id]}: #{c[:name]}" }.join("\n")}
    PROMPT
  end

  def parse_response(text)
    data = JSON.parse(text.to_s)

    {
      store_name: data['store_name'].presence,
      items:      Array(data['items']).select { |item| item.is_a?(Hash) }
    }
  rescue JSON::ParserError => e
    raise "Failed to parse Claude response: #{e.message}\nResponse: #{text&.truncate(500)}"
  end
end
