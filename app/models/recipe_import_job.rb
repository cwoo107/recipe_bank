class RecipeImportJob < ApplicationRecord
  belongs_to :recipe, optional: true
  belongs_to :user

  # Progress for the import page, broadcast over Action Cable (Redis) from
  # wherever the update happens — mostly the Sidekiq worker running
  # ProcessRecipeImportJob. Sent synchronously rather than via broadcasts_to's
  # queued path, so each update goes out as it happens instead of waiting
  # behind the import in the same queue.
  #
  # They're best-effort: a broadcast that fails (Redis unreachable for a
  # moment, say) is logged, not raised. These run after the job's own update
  # has committed, so raising would surface in the importer as if the import
  # itself had failed — including after the recipe was already saved. The
  # progress page shows the job's real state on its next load either way.
  after_create_commit  -> { broadcast_safely { broadcast_replace_to "recipe_import_#{id}" } }
  after_update_commit  -> { broadcast_safely { broadcast_replace_to "recipe_import_#{id}" } }
  after_destroy_commit -> { broadcast_safely { broadcast_remove_to  "recipe_import_#{id}" } }

  enum :status, {
    pending:               'pending',
    fetching_html:         'fetching_html',
    parsing_recipe:        'parsing_recipe',
    matching_ingredients:  'matching_ingredients',
    awaiting_confirmation: 'awaiting_confirmation',
    resolving_with_ai:     'resolving_with_ai',
    creating_recipe:       'creating_recipe',
    completed:             'completed',
    failed:                'failed'
  }

  # One row of the confirmation screen: what the recipe called for, and what
  # the matcher thinks it is in our ingredient list.
  IngredientMatch = Struct.new(
    :index, :original, :name, :quantity, :unit,
    :match_id, :match_name, :confidence, :match_method, :confirmed,
    keyword_init: true
  ) do
    def matched? = match_id.present?

    def confidence_percent = ((confidence || 0) * 100).round

    # Anything the user hasn't confirmed becomes a brand-new ingredient.
    def creates_new_ingredient? = !matched?
  end

  # Statuses of an import that's still running on its own.
  IN_PROGRESS_STATUSES = %w[pending fetching_html parsing_recipe matching_ingredients
                            resolving_with_ai creating_recipe].freeze

  # An import can still be cut off mid-run — a worker killed outright on a
  # deploy — or predate the move to Sidekiq, when imports ran on a thread in
  # the web process and every restart stranded one. These are the ones that
  # look abandoned: running (or never started) with no progress for an hour, or
  # left waiting on the user's confirmation for a week — plus any left over
  # from before status was a string enum (raw values like "7" that no
  # status maps to). See recipe_imports:clear_stuck.
  STUCK_AFTER                  = 1.hour
  ABANDONED_CONFIRMATION_AFTER = 7.days

  scope :stuck, -> {
    where(status: IN_PROGRESS_STATUSES + [ nil ]).where(updated_at: ...STUCK_AFTER.ago)
      .or(where(status: "awaiting_confirmation").where(updated_at: ...ABANDONED_CONFIRMATION_AFTER.ago))
      .or(where.not(status: statuses.values))
  }

  # Atomically moves a job from awaiting_confirmation to resolving_with_ai.
  # Only one caller can win — a second submit of the confirmation form (two
  # tabs, a resubmitted request) gets false and doesn't start a second run
  # that would save the recipe twice.
  def claim_confirmation!
    claimed = self.class.where(id: id, status: "awaiting_confirmation")
                        .update_all(status: "resolving_with_ai", updated_at: Time.current) == 1
    reload if claimed
    claimed
  end

  def update_progress(step, current = nil, total = nil)
    updates = { status: step, current_step: step.to_s.humanize }
    updates[:progress]    = current if current
    updates[:total_steps] = total   if total
    update!(updates)
  end

  def ingredient_count
    scraped_data&.dig('ingredients')&.length || 0
  end

  # The persisted match rows, wrapped for display. `index` is the row's
  # position, which is what the confirmation form posts back.
  def ingredient_matches
    Array(matched_ingredients).each_with_index.filter_map do |row, index|
      next unless row.is_a?(Hash)

      parsed = row['parsed'] || {}
      IngredientMatch.new(
        index:        index,
        original:     parsed['original'],
        name:         parsed['name'],
        quantity:     parsed['quantity'],
        unit:         parsed['unit'],
        match_id:     row['match_id'],
        match_name:   row['match_name'],
        confidence:   row['confidence'],
        match_method: row['method'],
        confirmed:    row['confirmed']
      )
    end
  end

  # Records the user's decisions. A row the user didn't tick loses its match,
  # so the importer creates a new ingredient for it instead.
  def apply_ingredient_confirmations!(confirmed_indexes)
    # filter_map over to_i: a blank or junk value must not coerce to 0 and
    # silently confirm the first row.
    confirmed = confirmed_indexes.filter_map { |i| Integer(i, exception: false) }.to_set

    rows = Array(matched_ingredients).each_with_index.map do |row, index|
      next row unless row.is_a?(Hash)

      row = row.dup
      if confirmed.include?(index) && row['match_id'].present?
        row['confirmed'] = true
      else
        row['confirmed']  = false
        row['match_id']   = nil
        row['match_name'] = nil
        row['confidence'] = 0.0
        row['method']     = 'user_new'
      end
      row
    end

    update!(matched_ingredients: rows)
  end

  def matched_ingredient_count
    if matched_ingredients.present?
      matched_ingredients.count { |r| r.is_a?(Hash) && r['match_id'].present? }
    elsif matching_ingredients?
      progress.to_i
    else
      0
    end
  end

  def new_ingredient_count = ingredient_matches.count(&:creates_new_ingredient?)

  # The recipe this import saved, if it got that far — whatever its status.
  def saved_recipe = recipe_id.present? ? Recipe.find_by(id: recipe_id) : nil

  def ingredient_match_summary
    total = ingredient_count
    return "Matching ingredients" if total.zero?

    if matching_ingredients?
      "Matching ingredients (#{progress.to_i} / #{total})"
    else
      "Matched #{matched_ingredient_count} of #{total} ingredients"
    end
  end

  private

  def broadcast_safely
    yield
  rescue => e
    Rails.logger.error "RecipeImportJob ##{id}: progress broadcast failed (#{e.class}: #{e.message}) — " \
                       "the import carries on; the page shows the real state on reload"
  end
end
