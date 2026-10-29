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
  # Images claiming more pixels than this are refused before decoding: a
  # small file can declare enormous dimensions (a "pixel flood") and
  # exhaust memory once decoded. Well above any phone camera.
  MAX_PIXELS = 100_000_000

  # What an upload actually is, read from its first bytes — not the
  # browser's Content-Type, which whoever uploads it controls. nil unless
  # it's a type we can send.
  def self.content_type_of(io)
    type = Marcel::MimeType.for(io)
    io.rewind
    type if SUPPORTED_TYPES.include?(type)
  end

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

  # The photo as a JPEG no bigger than MAX_DIMENSION, decoded in memory
  # with libvips (nothing is written to disk). Raises rather than sending
  # the original when it can't be read.
  def compressed_image_data
    require 'vips'
    # Uploads are only ever JPEG/PNG/GIF/WebP; keep libvips off its loaders
    # that aren't meant for untrusted input.
    Vips.block_untrusted(true)

    data = @file.read
    @file.rewind

    # Only the header is read here, so the size check comes before decoding.
    header = Vips::Image.new_from_buffer(data, '')
    if header.width * header.height > MAX_PIXELS
      raise "That image is too large to read — please upload a smaller photo."
    end

    image = Vips::Image.thumbnail_buffer(data, MAX_DIMENSION, height: MAX_DIMENSION, size: :down)
    image = image.colourspace(:srgb)
    image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?
    image.jpegsave_buffer(Q: JPEG_QUALITY, strip: true)
  rescue Vips::Error => e
    Rails.logger.warn "Image decoding failed: #{e.message}"
    raise "We couldn't read that image — please try a JPEG or PNG photo."
  end
end
