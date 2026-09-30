# Audits ingredient names and plans their cleanup (see
# IngredientNameNormalizer), for the ingredients:normalize_names task:
#
#   audit = Ingredient::NameAudit.new                 # every ingredient
#   audit = Ingredient::NameAudit.new(household: h)   # just one household's
#   audit.changes  # => [Change, …] — what would happen, for review
#   audit.apply!   # renames and merges, in one transaction
#
# Two kinds of change:
#   - rename: the name is cleaned in place.
#   - merge:  once cleaned, two ingredients in the same household (and with
#             the same brand) turn out to be the same thing — "All purpose
#             flour" and "All-purpose flour". The duplicate's recipe lines,
#             grocery rows, tags, nutrition facts and copies move to the one
#             kept, and the duplicate is deleted.
# Households never merge with each other; each keeps its own library.
class Ingredient::NameAudit
  Change = Struct.new(:kind, :ingredient, :to_name, :into, :notes, keyword_init: true) do
    def rename? = kind == :rename
    def merge?  = kind == :merge
  end

  def initialize(household: nil)
    @scope = household ? Ingredient.where(household: household) : Ingredient.all
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

  # Loose identity for spotting duplicates: case, spacing and punctuation
  # don't matter ("All purpose flour" == "All-purpose flour").
  def self.match_key(name) = name.to_s.downcase.gsub(/[^[:alnum:]]/, "")

  private

  def plan
    ingredients = @scope.includes(:household).order(:id).to_a
    usage       = RecipeIngredient.where(ingredient_id: ingredients.map(&:id)).group(:ingredient_id).count
    cleaned     = ingredients.to_h { |ingredient| [ ingredient, IngredientNameNormalizer.call(ingredient.ingredient) ] }

    groups = ingredients.group_by do |ingredient|
      [ ingredient.household_id, self.class.match_key(cleaned[ingredient].name), ingredient.brand.to_s.strip.downcase ]
    end

    groups.values.flat_map do |group|
      keeper = pick_keeper(group, cleaned, usage)
      result = []

      (group - [ keeper ]).each do |duplicate|
        result << Change.new(kind: :merge, ingredient: duplicate, to_name: cleaned[keeper].name, into: keeper,
                             notes: cleaned[duplicate].notes)
      end

      if cleaned[keeper].changed_from?(keeper.ingredient)
        result << Change.new(kind: :rename, ingredient: keeper, to_name: cleaned[keeper].name, notes: cleaned[keeper].notes)
      elsif cleaned[keeper].notes.any?
        # Name's fine as-is but still worth a look (e.g. two ingredients in one).
        result << Change.new(kind: :review, ingredient: keeper, to_name: keeper.ingredient, notes: cleaned[keeper].notes)
      end

      result
    end
  end

  # Keep the one that's already clean if there is one, then the most used,
  # then the oldest.
  def pick_keeper(group, cleaned, usage)
    group.min_by do |ingredient|
      [ cleaned[ingredient].changed_from?(ingredient.ingredient) ? 1 : 0, -usage.fetch(ingredient.id, 0), ingredient.id ]
    end
  end

  def merge(duplicate, into:)
    keeper = into

    RecipeIngredient.where(ingredient: duplicate).update_all(ingredient_id: keeper.id)
    Ingredient.where(source_ingredient: duplicate).update_all(source_ingredient_id: keeper.id)
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
