# app/models/recipe_file_extractor.rb
#
# Reads a recipe out of an uploaded photo or PDF with Claude Haiku (the
# official SDK), getting back JSON in RECIPE_SCHEMA (structured outputs).
require 'base64'

class RecipeFileExtractor
  MODEL = 'claude-haiku-5-5'

  RECIPE_SCHEMA = {
    type: 'object',
    properties: {
      title:       { type: 'string' },
      description: { anyOf: [ { type: 'string' }, { type: 'null' } ] },
      servings:    { anyOf: [ { type: 'integer' }, { type: 'null' } ] },
      ingredients: { type: 'array', items: { type: 'string' } },
      steps:       { type: 'array', items: { type: 'string' } }
    },
    required: %w[title description servings ingredients steps],
    additionalProperties: false
  }.freeze

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

  # The JSON text of Claude's answer. Raises (the import shows it as failed)
  # when there isn't one — an API error, a refusal, or a reply cut short.
  def call_claude
    response = Anthropic::Client.new(timeout: 120).messages.create(
      model:         MODEL,
      max_tokens:    16_000,
      output_config: { effort: :medium, format_: { type: :json_schema, schema: RECIPE_SCHEMA } },
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
      raise "Claude couldn't read the recipe (stop_reason #{response.stop_reason}#{" — #{response.stop_details&.category}" if response.stop_reason == :refusal})"
    end

    # The answer is the text block — Haiku can put thinking blocks first.
    response.content.find { |block| block.type == :text }&.text
  rescue Anthropic::Errors::APIStatusError => e
    raise "Claude API error: #{e.status} — #{e.message}"
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
      Extract the recipe from this file: its title, description, servings,
      ingredients and steps.

      Rules:
      - ingredients: keep the original text including quantities and units (e.g. "2 cups all-purpose flour")
      - steps: each step as a complete sentence, numbered steps without the number
      - servings: extract as an integer if present, otherwise null
      - description: one sentence summary if not provided in the recipe, otherwise null
    PROMPT
  end

  def parse_response(text)
    data = JSON.parse(text.to_s)

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