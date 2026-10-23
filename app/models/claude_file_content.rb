# The content block for an uploaded photo or PDF in a Claude message —
# shared by RecipeFileExtractor and ReceiptExtractor. Expects @file (an IO
# with #read and #rewind) and @content_type.
require 'base64'

module ClaudeFileContent
  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  SUPPORTED_TYPES = (SUPPORTED_IMAGE_TYPES + ['application/pdf']).freeze

  # Max dimension for images before sending to Claude — reduces payload dramatically
  MAX_DIMENSION = 1568
  # Target JPEG quality after resize
  JPEG_QUALITY = 85

  private

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
end
