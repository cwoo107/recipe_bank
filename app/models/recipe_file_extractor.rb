# app/models/recipe_file_extractor.rb
require 'base64'
require 'httparty'

class RecipeFileExtractor
  ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages'

  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  SUPPORTED_TYPES = (SUPPORTED_IMAGE_TYPES + ['application/pdf']).freeze

  # Max dimension for images before sending to Claude — reduces payload dramatically
  MAX_DIMENSION = 1568
  # Target JPEG quality after resize
  JPEG_QUALITY = 85

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
        'x-api-key'         => ENV.fetch('ANTHROPIC_API_KEY'),
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
              { type: 'text', text: extraction_prompt }
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
    if @content_type == 'application/pdf'
      data = Base64.strict_encode64(@file.read)
      @file.rewind
      { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: data } }
    else
      data = Base64.strict_encode64(compressed_image_data)
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: data } }
    end
  end

  def compressed_image_data
    require 'mini_magick'

    image = MiniMagick::Image.read(@file.read)
    @file.rewind

    # Resize if either dimension exceeds MAX_DIMENSION, preserving aspect ratio
    if image.width > MAX_DIMENSION || image.height > MAX_DIMENSION
      image.resize "#{MAX_DIMENSION}x#{MAX_DIMENSION}>"
    end

    # Convert to JPEG and compress
    image.format 'jpeg'
    image.quality JPEG_QUALITY.to_s

    image.to_blob
  rescue => e
    Rails.logger.warn "Image compression failed (#{e.message}), using original"
    @file.rewind
    @file.read
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