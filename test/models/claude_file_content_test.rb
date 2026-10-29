require "test_helper"

class ClaudeFileContentTest < ActiveSupport::TestCase
  class Reader
    include ClaudeFileContent

    def initialize(bytes)
      @file = StringIO.new(bytes)
      @content_type = ClaudeFileContent.content_type_of(@file)
    end

    attr_reader :content_type

    def block = file_content_block
  end

  def png(width, height, bands: 3)
    require "vips"
    Vips::Image.black(width, height, bands: bands).pngsave_buffer
  end

  test "an upload's type is read from its bytes" do
    assert_equal "image/png", Reader.new(png(10, 10)).content_type
    assert_equal "application/pdf", Reader.new("%PDF-1.4 x").content_type
    assert_nil Reader.new("<svg xmlns='http://www.w3.org/2000/svg'/>").content_type
    assert_nil Reader.new("just text").content_type
  end

  test "a large photo is shrunk and sent as a JPEG" do
    block = Reader.new(png(3000, 2000, bands: 4)).block

    assert_equal "image/jpeg", block.dig(:source, :media_type)
    image = Vips::Image.new_from_buffer(Base64.strict_decode64(block.dig(:source, :data)), "")
    assert_equal [ 1568, 1045, 3 ], [ image.width, image.height, image.bands ]
  end

  test "an image claiming enormous dimensions is refused before it's decoded" do
    error = assert_raises(RuntimeError) { Reader.new(png(12_000, 12_000)).block }
    assert_match "too large", error.message
  end

  test "an image that can't be decoded is refused rather than sent as is" do
    error = assert_raises(RuntimeError) { Reader.new("\x89PNG\r\n\x1A\n broken".b).block }
    assert_match "couldn't read that image", error.message
  end
end
