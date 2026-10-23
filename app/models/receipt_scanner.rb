# Reads a ReceiptScan's upload and matches its lines to the household's
# ingredients, then leaves it waiting for the user's review. Runs on the
# worker (ProcessReceiptScanJob); the upload waits on the scan until then
# and is cleared once read, whether or not reading succeeds.
class ReceiptScanner
  def initialize(scan)
    @scan = scan
  end

  def perform
    @scan.update!(status: :reading_receipt)

    file_data, content_type = @scan.source_file, @scan.source_content_type
    raise "The uploaded receipt is no longer available — please upload it again." if file_data.blank?
    @scan.update!(source_file: nil)

    file_io = StringIO.new(file_data)
    file_io.define_singleton_method(:content_type) { content_type }

    result = ReceiptExtractor.new(file_io, candidates: candidates).extract
    raise "We couldn't find any items on that receipt — try a clearer photo." if result[:items].empty?

    @scan.update!(status: :matching_items)
    @scan.update!(
      store_name: result[:store_name],
      items:      result[:items].map { |item| clean(item) },
      status:     :awaiting_confirmation
    )
  rescue => e
    Rails.logger.error "=== RECEIPT SCAN ERROR ==="
    Rails.logger.error e.message
    Rails.logger.error e.backtrace&.join("\n")

    @scan.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def household = @scan.household

  # What a receipt line can be matched to (ReceiptScan#matchable_ingredients).
  # The ones on grocery lists around the scan's week go first, so they make
  # the cut if the household has more than the prompt can hold.
  def candidates
    @candidates ||= begin
      nearby = household.grocery_lists
                        .where(week_of: (@scan.week_of - 7)...(@scan.week_of + 14))
                        .where.not(ingredient_id: nil)
                        .distinct.pluck(:ingredient_id).to_set

      @scan.matchable_ingredients.where.not(ingredient: [ nil, "" ]).pluck(:id, :ingredient)
           .sort_by { |id, _name| nearby.include?(id) ? 0 : 1 }
           .first(ReceiptExtractor::MAX_CANDIDATES)
           .map { |id, name| { id: id, name: name } }
    end
  end

  # Keeps only the fields we use, and drops a match to an ingredient the
  # model wasn't offered.
  def clean(item)
    ingredient_id = item['ingredient_id']
    ingredient_id = nil unless candidate_ids.include?(ingredient_id)

    {
      'text'          => item['text'].to_s,
      'name'          => item['name'].to_s,
      'quantity'      => item['quantity'],
      'unit_price'    => item['unit_price'],
      'total_price'   => item['total_price'],
      'by_weight'     => item['by_weight'] == true,
      'ingredient_id' => ingredient_id
    }
  end

  def candidate_ids
    @candidate_ids ||= candidates.map { |c| c[:id] }.to_set
  end
end
