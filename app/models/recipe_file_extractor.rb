# app/services/recipe_file_extractor.rb
# Sends an uploaded file (image or PDF) to Claude and extracts recipe data
# in the same format that RecipeScraper returns.

require 'base64'
require 'httparty'

class RecipeFileExtractor
  ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages'

  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  SUPPORTED_TYPES = (SUPPORTED_IMAGE_TYPES + ['application/pdf']).freeze

  def initialize(file)
    @file = file
    @content_type = file.content_type
  end

  def extract
    raise "Unsupported file type: #{@content_type}" unless SUPPORTED_TYPES.include?(@content_type)

    response = call_claude
    parse_response(response)
  end

  private

  def call_claude
    response = HTTParty.post(
      ANTHROPIC_API_URL,
      headers: {
        'Content-Type'      => 'application/json',
        'x-api-key'         => "ENV.fetch('ANTHROPIC_API_KEY')",
        'anthropic-version' => '2023-06-01'
      },
      body: {
        model:      'claude-haiku-4-5-20251001',
        max_tokens: 4096,
        messages:   [
          {
            role:    'user',
            content: [
              file_content_block,
              {
                type: 'text',
                text: extraction_prompt
              }
            ]
          }
        ]
      }.to_json,
      timeout: 60
    )

    raise "Claude API error: #{response.code} — #{response.body}" unless response.success?

    body = JSON.parse(response.body)
    body.dig('content', 0, 'text')
  end

  def file_content_block
    data = Base64.strict_encode64(@file.read)
    @file.rewind

    if @content_type == 'application/pdf'
      {
        type:   'document',
        source: { type: 'base64', media_type: 'application/pdf', data: data }
      }
    else
      {
        type:   'image',
        source: { type: 'base64', media_type: @content_type, data: data }
      }
    end
  end

  def extraction_prompt
    <<~PROMPT
      Extract the recipe from this file and return it as JSON only — no explanation, no markdown fences.

      Return exactly this structure:
      {
        "title": "Recipe name",
        "description": "Brief description or null",
        "servings": number or null,
        "ingredients": ["1 cup flour", "2 eggs", ...],
        "steps": ["Preheat oven to 350F.", "Mix dry ingredients.", ...]
      }

      Rules:
      - ingredients: keep the original text including quantities and units (e.g. "2 cups all-purpose flour")
      - steps: each step as a complete sentence, numbered steps without the number
      - servings: extract as an integer if present, otherwise null
      - description: one sentence summary if not provided in the recipe, otherwise null
      - Return ONLY the JSON object, nothing else
    PROMPT
  end

  def parse_response(text)
    # Strip any accidental markdown fences
    cleaned = text.to_s.gsub(/```json\n?|\n?```/, '').strip
    data = JSON.parse(cleaned)

    {
      title:       data['title'],
      description: data['description'],
      servings:    data['servings']&.to_i,
      ingredients: Array(data['ingredients']),
      steps:       Array(data['steps']),
      image_url:   nil
    }
  rescue JSON::ParserError => e
    raise "Failed to parse Claude response: #{e.message}\nResponse: #{text&.truncate(500)}"
  end
end