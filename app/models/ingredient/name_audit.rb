# Audits ingredient names and plans their cleanup (see
# IngredientNameNormalizer), for the ingredients:normalize_names task:
#
#   audit = Ingredient::NameAudit.new                 # every household
#   audit = Ingredient::NameAudit.new(household: h)   # just one household's
#   audit.changes  # => [Change, …] — what would happen, for review
#   audit.apply!   # renames and merges, in one transaction
#
# Kinds of change:
#   - rename: the name is cleaned in place.
#   - merge:  once cleaned, two ingredients in the same household are the
#             same ingredient by the app's own rule (Ingredient#copy_for):
#             same name, ignoring case, and same brand. The duplicate's
#             recipe lines, grocery rows, tags, nutrition facts and copies
#             move to the one kept, and the duplicate is deleted.
#   - review: left as is, with notes for a person to look at.
#
# It works within the per-household ingredient libraries, never against
# them:
#   - Each household has its own copy of an ingredient on purpose, so the
#     same name in two households is expected and never merged.
#   - The shared catalog (no household) is left alone — it's copied from,
#     never edited in place.
#   - Only the app's exact same-ingredient rule merges anything. Names that
#     merely look alike ("All purpose flour" / "All-purpose flour") are
#     flagged for review, not merged.
#   - A guessed cleanup (one with notes, like "See brown sugar alternative"
#     → "Brown sugar") never merges into another ingredient; if it would
#     collide with one, it's left for review instead.
#   - The link from a household copy back to what it was copied from
#     (source_ingredient) is kept, so importing or copying that recipe again
#     finds the same copy rather than making a new duplicate. Two copies of
#     different originals aren't merged, since only one link could survive.
class Ingredient::NameAudit
  Change = Struct.new(:kind, :ingredient, :to_name, :into, :notes, keyword_init: true) do
    def rename? = kind == :rename
    def merge?  = kind == :merge
  end

  def initialize(household: nil)
    households = Ingredient.where.not(household_id: nil)
    @scope = household ? households.where(household: household) : households
  end

  def changes
    @changes ||= plan
  end

  def apply!
    Ingredient.transaction do
      changes.select(&:merge?).each { |change| merge(change.ingredient, into: change.into) }
      changes.select(&:rename?).each { |change| change.ingredient.update!(ingredient: change.to_name) }
    end
  end

  # The app's rule for "the same ingredient" within a household — mirrors
  # Ingredient#household_equivalent: name ignoring case and surrounding
  # space, plus brand the same way.
  def self.same_ingredient_key(name, brand) = [ name.to_s.strip.downcase, brand.to_s.strip.downcase ]

  # Looser, for flagging names that only look alike ("All purpose flour" /
  # "All-purpose flour"): case, spacing and punctuation don't matter.
  def self.lookalike_key(name) = name.to_s.downcase.gsub(/[^[:alnum:]]/, "")

  private

  def plan
    ingredients = @scope.includes(:household).order(:id).to_a
    @usage      = RecipeIngredient.where(ingredient_id: ingredients.map(&:id)).group(:ingredient_id).count
    @cleaned    = ingredients.to_h { |ingredient| [ ingredient, IngredientNameNormalizer.call(ingredient.ingredient) ] }
    @changes_by = {}

    groups = ingredients.group_by do |ingredient|
      [ ingredient.household_id, *self.class.same_ingredient_key(@cleaned[ingredient].name, ingredient.brand) ]
    end
    groups.each_value { |group| plan_group(group) }

    flag_lookalikes(ingredients)
    @changes_by.values
  end

  def plan_group(group)
    keeper = pick_keeper(group)

    (group - [ keeper ]).each do |duplicate|
      if guessed?(duplicate)
        review duplicate, "would become a duplicate of ##{keeper.id} \"#{keeper.ingredient}\" once cleaned — " \
                          "left as is; merge it by hand if it's really the same"
        @cleaned[duplicate].notes.each { |note| review duplicate, note }
      elsif conflicting_sources?(duplicate, keeper)
        review duplicate, "same as ##{keeper.id} \"#{keeper.ingredient}\", but each is a copy of a different " \
                          "original — not merged, so both copy links stay intact"
      else
        @changes_by[duplicate] = Change.new(kind: :merge, ingredient: duplicate, to_name: @cleaned[keeper].name,
                                            into: keeper, notes: @cleaned[duplicate].notes)
      end
    end

    if @cleaned[keeper].changed_from?(keeper.ingredient)
      @changes_by[keeper] = Change.new(kind: :rename, ingredient: keeper, to_name: @cleaned[keeper].name,
                                       notes: @cleaned[keeper].notes)
    elsif @cleaned[keeper].notes.any?
      # Name's fine as-is but still worth a look (e.g. two ingredients in one).
      @cleaned[keeper].notes.each { |note| review keeper, note }
    end
  end

  # Names that aren't the same ingredient by the app's rule but look like
  # it — reported, never merged.
  def flag_lookalikes(ingredients)
    remaining = ingredients.reject { |ingredient| @changes_by[ingredient]&.merge? } # merged ones are going away
    remaining.group_by { |ingredient| [ ingredient.household_id, self.class.lookalike_key(final_name(ingredient)), ingredient.brand.to_s.strip.downcase ] }
               .each_value do |group|
      next if group.map { |ingredient| final_name(ingredient).strip.downcase }.uniq.size < 2

      reference = group.max_by { |ingredient| [ @usage.fetch(ingredient.id, 0), -ingredient.id ] }
      (group - [ reference ]).each do |ingredient|
        next if final_name(ingredient).strip.casecmp?(final_name(reference).strip)

        review ingredient, "looks like the same thing as ##{reference.id} \"#{final_name(reference)}\" — " \
                           "not merged, since differently spelled names count as different ingredients"
      end
    end
  end

  # What the ingredient will be called once this audit's changes are applied.
  def final_name(ingredient)
    change = @changes_by[ingredient]
    change&.rename? ? change.to_name : ingredient.ingredient
  end

  # The cleanup involved a judgement call (it has notes) and changed the name.
  def guessed?(ingredient)
    @cleaned[ingredient].changed_from?(ingredient.ingredient) && @cleaned[ingredient].notes.any?
  end

  # Compares against the link the keeper will end up with — its own, or one
  # inherited from a duplicate already planned to merge into it — so two
  # duplicates copied from different originals can't both merge in.
  def conflicting_sources?(duplicate, keeper)
    @planned_source ||= {}
    source = @planned_source.fetch(keeper) { keeper.source_ingredient_id }
    return false if duplicate.source_ingredient_id.blank? || duplicate.source_ingredient_id == keeper.id
    return false if source.blank? && (@planned_source[keeper] = duplicate.source_ingredient_id)

    source != duplicate.source_ingredient_id
  end

  # Adds a note to the ingredient's planned change, or makes it a review.
  def review(ingredient, note)
    change = (@changes_by[ingredient] ||= Change.new(kind: :review, ingredient: ingredient, to_name: ingredient.ingredient, notes: []))
    change.notes = (change.notes + [ note ]).uniq
  end

  # Keep the one that's already clean if there is one, then a confident
  # cleanup over a guessed one, then the most used, then the oldest.
  def pick_keeper(group)
    group.min_by do |ingredient|
      [ @cleaned[ingredient].changed_from?(ingredient.ingredient) ? 1 : 0, guessed?(ingredient) ? 1 : 0,
        -@usage.fetch(ingredient.id, 0), ingredient.id ]
    end
  end

  def merge(duplicate, into:)
    keeper = into

    RecipeIngredient.where(ingredient: duplicate).update_all(ingredient_id: keeper.id)
    # Other households' copies made from the duplicate now trace back to the
    # kept one.
    Ingredient.where(source_ingredient: duplicate).update_all(source_ingredient_id: keeper.id)
    # And if the duplicate was itself a copy, the kept one inherits that link
    # (plan never merges two copies of different originals), so
    # Ingredient#copy_for finds it next time instead of making a new copy.
    if keeper.source_ingredient_id.nil? && duplicate.source_ingredient_id.present? &&
       duplicate.source_ingredient_id != keeper.id
      keeper.update_columns(source_ingredient_id: duplicate.source_ingredient_id)
    end
    merge_grocery_rows(duplicate, keeper)

    duplicate.ingredient_tags.where.not(tag_id: keeper.ingredient_tags.select(:tag_id)).update_all(ingredient_id: keeper.id)

    if keeper.nutrition_fact.nil? && duplicate.nutrition_fact
      duplicate.nutrition_fact.update_columns(ingredient_id: keeper.id)
    end

    # Fill in anything the kept one is missing.
    fill = %w[family unit_price unit_servings organic favorite].each_with_object({}) do |attribute, missing|
      missing[attribute] = duplicate[attribute] if keeper[attribute].nil? && !duplicate[attribute].nil?
    end
    keeper.update_columns(fill) if fill.any?

    duplicate.reload.destroy!
  end

  # A grocery list can have the duplicate and the kept one on the same week
  # — combine them into one row rather than listing it twice.
  def merge_grocery_rows(duplicate, keeper)
    GroceryList.where(ingredient: duplicate).find_each do |row|
      existing = GroceryList.find_by(ingredient: keeper, household_id: row.household_id, week_of: row.week_of)
      if existing
        existing.update_columns(units: existing.units.to_i + row.units.to_i)
        row.delete
      else
        row.update_columns(ingredient_id: keeper.id)
      end
    end
  end
end
