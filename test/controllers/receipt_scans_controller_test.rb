require "test_helper"
require "minitest/mock"

# "Upload Receipt" on the grocery list: the upload is read on Sidekiq, then
# the user reviews the matches and the week before anything is checked off.
class ReceiptScansControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user      = users(:one)
    @household = households(:one)
    @week      = Date.new(2026, 2, 9) # a Monday, like the fixtures' lists
    @milk  = Ingredient.create!(household: @household, ingredient: "Whole milk", family: "dairy", unit_price: 3.29)
    @eggs  = Ingredient.create!(household: @household, ingredient: "Eggs", family: "protein", unit_price: 4.00)
    @bread = Ingredient.create!(household: @household, ingredient: "Bread", family: "grains", unit_price: 2.50)
    @milk_line  = @household.grocery_lists.create!(user: @user, ingredient: @milk, units: 1, week_of: @week, checked: false)
    @eggs_line  = @household.grocery_lists.create!(user: @user, ingredient: @eggs, units: 1, week_of: @week, checked: false)
    @bread_line = @household.grocery_lists.create!(user: @user, ingredient: @bread, units: 1, week_of: @week, checked: false)

    sign_in @user
  end

  def scan_with(items, week_of: @week)
    @household.receipt_scans.create!(user: @user, week_of: week_of, status: :awaiting_confirmation,
                                     store_name: "Corner Market", items: items)
  end

  def line(text, ingredient, price, quantity: 1, by_weight: false)
    { "text" => text, "name" => text.downcase, "quantity" => quantity, "unit_price" => price,
      "total_price" => (price * quantity).round(2), "by_weight" => by_weight, "ingredient_id" => ingredient&.id }
  end

  test "the grocery list links to the upload page for the week being shown" do
    get grocery_lists_url(date: @week)
    assert_select "a[href=?]", new_receipt_scan_path(date: @week), text: /Upload Receipt/
  end

  test "the upload page defaults to the week it came from, with previous and next weeks" do
    get new_receipt_scan_url(date: @week + 3)

    assert_response :success
    assert_select "input[name=week_of][value=?]", @week.to_s
    assert_select "a[href=?]", new_receipt_scan_path(date: @week - 7)
    assert_select "a[href=?]", new_receipt_scan_path(date: @week + 7)
  end

  JPEG_BYTES = "\xFF\xD8\xFF\xE0 fake jpeg".b.freeze

  test "uploading keeps the photo on the scan for the worker, and enqueues it" do
    upload = Rack::Test::UploadedFile.new(StringIO.new(JPEG_BYTES), "image/jpeg", original_filename: "receipt.jpg")

    post receipt_scans_url, params: { file: upload, week_of: @week.to_s }

    scan = ReceiptScan.last
    assert_redirected_to receipt_scan_path(scan)
    assert_equal JPEG_BYTES, scan.source_file
    assert_equal "image/jpeg", scan.source_content_type
    assert_equal @week, scan.week_of
    assert scan.pending?
    assert_enqueued_with(job: ProcessReceiptScanJob, args: [ scan.id ])
  end

  test "an unsupported file is turned away" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "receipt.txt")

    assert_no_difference("ReceiptScan.count") do
      post receipt_scans_url, params: { file: upload, week_of: @week.to_s }
    end
    assert_redirected_to new_receipt_scan_path(date: @week)
  end

  test "a file is judged by its contents, not the type the browser claims" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'/>"), "image/jpeg",
                                          original_filename: "receipt.jpg")

    assert_no_difference("ReceiptScan.count") do
      post receipt_scans_url, params: { file: upload, week_of: @week.to_s }
    end
    assert_redirected_to new_receipt_scan_path(date: @week)
    assert_no_enqueued_jobs only: ProcessReceiptScanJob
  end

  test "a file field sent as plain text is turned away rather than erroring" do
    assert_no_difference("ReceiptScan.count") do
      post receipt_scans_url, params: { file: "not a file", week_of: @week.to_s }
    end
    assert_redirected_to new_receipt_scan_path(date: @week)
  end

  test "the worker drops amounts that aren't sensible" do
    upload_scan = @household.receipt_scans.create!(user: @user, week_of: @week, source_file: "jpeg", source_content_type: "image/jpeg")
    extracted = { store_name: nil,
                  items: [ line("GV WHL MLK", @milk, 3.49).merge("unit_price" => -5, "total_price" => 1e9, "quantity" => "2") ] }

    fake = Minitest::Mock.new
    fake.expect(:extract, extracted)
    ReceiptExtractor.stub(:new, ->(*, **) { fake }) do
      ProcessReceiptScanJob.perform_now(upload_scan.id)
    end

    item = upload_scan.reload.items.first
    assert_nil item["unit_price"]
    assert_nil item["total_price"]
    assert_nil item["quantity"]
  end

  test "the review shows each line beside its match, and offers changed prices" do
    scan = scan_with([ line("GV WHL MLK", @milk, 3.49), line("LG EGGS", @eggs, 4.00), line("PAPER TOWEL", nil, 5.99) ])

    get receipt_scan_url(scan)

    assert_response :success
    assert_match "Review your receipt from Corner Market", response.body
    assert_match "GV WHL MLK", response.body
    assert_match "On this week&#39;s list", response.body
    assert_match "No match found", response.body
    assert_select "input#confirmed_0[checked]"
    assert_select "input#confirmed_2", count: 0
    # Milk went from $3.29 to $3.49; eggs are the same price.
    assert_select "input#price_update_0[checked]"
    assert_select "input#price_update_1", count: 0
  end

  test "applying checks off the kept lines and updates the ticked prices" do
    scan = scan_with([ line("GV WHL MLK", @milk, 3.49), line("LG EGGS", @eggs, 4.50), line("PAPER TOWEL", nil, 5.99) ])

    post apply_receipt_scan_url(scan), params: { confirmed: %w[0 1], price_updates: %w[0] }

    assert_redirected_to grocery_lists_path(date: @week)
    assert_match "Checked off 2 items", flash[:notice]
    assert_match "Updated 1 price", flash[:notice]
    assert @milk_line.reload.checked
    assert @eggs_line.reload.checked
    assert_not @bread_line.reload.checked
    assert_in_delta 3.49, @milk.reload.unit_price
    assert_in_delta 4.00, @eggs.reload.unit_price # not ticked
    assert scan.reload.applied?
  end

  test "an unticked match isn't checked off, and its price isn't taken" do
    scan = scan_with([ line("GV WHL MLK", @milk, 3.49) ])

    post apply_receipt_scan_url(scan), params: { price_updates: %w[0] }

    assert_not @milk_line.reload.checked
    assert_in_delta 3.29, @milk.reload.unit_price
  end

  test "items sold by weight aren't offered as price updates" do
    scan = scan_with([ line("BANANAS", @bread, 0.59, quantity: 2.3, by_weight: true) ])

    get receipt_scan_url(scan)
    assert_select "input#price_update_0", count: 0

    post apply_receipt_scan_url(scan), params: { confirmed: %w[0], price_updates: %w[0] }
    assert_in_delta 2.50, @bread.reload.unit_price
  end

  test "changing the week applies the receipt to that week's list instead" do
    next_week = @week + 7
    next_milk = @household.grocery_lists.create!(user: @user, ingredient: @milk, units: 1, week_of: next_week, checked: false)
    scan = scan_with([ line("GV WHL MLK", @milk, 3.29) ])

    patch receipt_scan_url(scan), params: { receipt_scan: { week_of: next_week.to_s } }
    assert_redirected_to receipt_scan_path(scan)
    assert_equal next_week, scan.reload.week_of

    post apply_receipt_scan_url(scan), params: { confirmed: %w[0] }

    assert_redirected_to grocery_lists_path(date: next_week)
    assert next_milk.reload.checked
    assert_not @milk_line.reload.checked
  end

  test "a receipt can only be applied once" do
    scan = scan_with([ line("GV WHL MLK", @milk, 3.49) ])
    post apply_receipt_scan_url(scan), params: { confirmed: %w[0] }
    @milk_line.reload.update!(checked: false)

    post apply_receipt_scan_url(scan), params: { confirmed: %w[0] }

    assert_redirected_to receipt_scan_path(scan)
    assert_not @milk_line.reload.checked
  end

  test "a match to another household's ingredient is ignored" do
    theirs = Ingredient.create!(household: households(:two), ingredient: "Their milk", family: "dairy", unit_price: 1)
    scan = scan_with([ line("MILK", theirs, 9.99) ])

    post apply_receipt_scan_url(scan), params: { confirmed: %w[0], price_updates: %w[0] }

    assert_in_delta 1.0, theirs.reload.unit_price
  end

  test "another household's scan can't be seen" do
    scan = households(:two).receipt_scans.create!(user: users(:three), week_of: @week, status: :awaiting_confirmation, items: [])

    get receipt_scan_url(scan)
    assert_response :not_found
  end

  test "the worker reads the receipt and keeps only matches it was offered" do
    upload_scan = @household.receipt_scans.create!(user: @user, week_of: @week, source_file: "jpeg", source_content_type: "image/jpeg")
    theirs = Ingredient.create!(household: households(:two), ingredient: "Their milk", family: "dairy")
    extracted = { store_name: "Corner Market",
                  items: [ line("GV WHL MLK", @milk, 3.49), line("THEIR MILK", theirs, 1.00) ] }

    fake = Minitest::Mock.new
    fake.expect(:extract, extracted)
    ReceiptExtractor.stub(:new, ->(_file, candidates:) {
      assert_includes candidates.map { |c| c[:id] }, @milk.id
      assert_not_includes candidates.map { |c| c[:id] }, theirs.id
      fake
    }) do
      ProcessReceiptScanJob.perform_now(upload_scan.id)
    end

    upload_scan.reload
    assert upload_scan.awaiting_confirmation?
    assert_nil upload_scan.source_file
    assert_equal "Corner Market", upload_scan.store_name
    assert_equal [ @milk.id, nil ], upload_scan.items.map { |i| i["ingredient_id"] }
  end

  test "a receipt the worker can't read is shown as failed" do
    upload_scan = @household.receipt_scans.create!(user: @user, week_of: @week, source_file: "jpeg", source_content_type: "image/jpeg")

    ReceiptExtractor.stub(:new, ->(*, **) { raise "Claude API error: 500" }) do
      ProcessReceiptScanJob.perform_now(upload_scan.id)
    end

    assert upload_scan.reload.failed?
    get receipt_scan_url(upload_scan)
    assert_match "Claude API error: 500", response.body
  end

  test "limited members can't upload receipts" do
    sign_in users(:two)
    get new_receipt_scan_url
    assert_response :redirect
  end
end
