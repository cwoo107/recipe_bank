require "test_helper"

# Step instructions are written in Trix, with attachments turned off and
# Active Storage's upload routes not mounted (config/application.rb).
class StepEditorTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
    @recipe = recipes(:one)
  end

  test "the new and edit step pages render the editor without upload URLs" do
    get new_recipe_step_url(@recipe)
    assert_response :success
    assert_select "trix-editor[data-direct-upload-url='']"

    get edit_recipe_step_url(@recipe, steps(:one))
    assert_response :success
    assert_select "trix-editor[data-direct-upload-url='']"
  end

  test "Active Storage's upload endpoints aren't there to use" do
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "x.pdf", byte_size: 1, checksum: "x", content_type: "application/pdf" } }
    assert_response :not_found
  end
end
