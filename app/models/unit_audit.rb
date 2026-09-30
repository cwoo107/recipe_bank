# Audits the units on recipe lines and nutrition facts and plans their
# cleanup (see UnitNormalizer), for the ingredients:normalize_units task —
# the units counterpart of Ingredient::NameAudit:
#
#   audit = UnitAudit.new                 # every household
#   audit = UnitAudit.new(household: h)   # just one household's
#   audit.changes  # => [Change, …] — one per distinct stored unit, for review
#   audit.apply!   # rewrites them, in one transaction
#
# Kinds of change:
#   - update: every row storing that exact value ("Tablespoons") gets the
#             picker's spelling ("tbsp"), or no unit for count words
#             ("whole").
#   - review: a unit the picker doesn't offer ("can", "stick") — left as is,
#             with a note for a person to look at.
#
# Only the unit's spelling changes, never an amount. Like the name audit,
# the shared ingredient catalog (no household) is left alone; its units are
# tidied as households copy from it (NutritionFact normalizes on save).
class UnitAudit
  Change = Struct.new(:kind, :source, :from, :to, :count, :notes, keyword_init: true) do
    def update? = kind == :update
  end

  # What's audited: a label for the report, the column, and its rows.
  Source = Struct.new(:label, :model, :column, keyword_init: true)

  SOURCES = [
    Source.new(label: "recipe lines", model: RecipeIngredient, column: :unit),
    Source.new(label: "nutrition facts", model: NutritionFact, column: :serving_unit)
  ].freeze

  def initialize(household: nil)
    @household = household
  end

  def changes
    @changes ||= SOURCES.flat_map { |source| plan(source) }
  end

  def apply!
    ActiveRecord::Base.transaction do
      changes.select(&:update?).each do |change|
        scope(change.source).where(change.source.column => change.from)
                            .update_all(change.source.column => change.to, updated_at: Time.current)
      end
    end
  end

  private

  def plan(source)
    scope(source).where.not(source.column => nil).group(source.column).count.filter_map do |value, count|
      result = UnitNormalizer.call(value)

      if result.changed_from?(value)
        Change.new(kind: :update, source:, from: value, to: result.unit, count:, notes: result.notes)
      elsif !result.recognized?
        Change.new(kind: :review, source:, from: value, to: value, count:, notes: result.notes)
      end
    end
  end

  def scope(source)
    case source.model.name
    when "RecipeIngredient"
      @household ? RecipeIngredient.joins(:recipe).where(recipes: { user_id: @household.users.select(:id) }) : RecipeIngredient.all
    when "NutritionFact"
      households = NutritionFact.joins(:ingredient).where.not(ingredients: { household_id: nil })
      @household ? households.where(ingredients: { household_id: @household.id }) : households
    end
  end
end
