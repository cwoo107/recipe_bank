require "csv"

# Loads the shared ingredient catalog (ingredients with no household — what
# households' imported and copied recipes draw on, see Ingredient#copy_for)
# from a CSV, for the ingredients:import_catalog task:
#
#   import = Ingredient::CatalogImport.new("db/ingredients.csv")
#   import.rows    # => [Row, …] — what would happen to each line, for review
#   import.apply!  # creates and updates, in one transaction
#
# Columns: ingredient, brand, family, organic, unit_price, unit_servings,
# serving_size, serving_unit, calories, protein, total_fat, total_carb.
#
# Each row is matched to the catalog by the app's same-ingredient rule —
# name ignoring case, plus brand — so the file can be edited and re-run:
#   - create:    not in the catalog yet.
#   - update:    in the catalog, and the file has different values for it.
#                A blank cell never clears a value that's already there.
#   - unchanged: in the catalog, already matching.
#   - invalid:   can't be imported as written (reasons given); skipped.
# Rows can also carry notes worth a look (a unit the picker doesn't offer, a
# name that saves with different capitals) without being skipped.
#
# Households' own copies are never touched — only the catalog.
class Ingredient::CatalogImport
  FAMILIES = IngredientsHelper::INGREDIENT_FAMILIES.keys.freeze

  INGREDIENT_COLUMNS = %w[ingredient brand family organic unit_price unit_servings].freeze
  NUTRITION_COLUMNS  = %w[serving_size serving_unit calories protein total_fat total_carb].freeze
  COLUMNS            = INGREDIENT_COLUMNS + NUTRITION_COLUMNS

  INTEGER_COLUMNS = %w[unit_servings calories].freeze
  DECIMAL_COLUMNS = %w[unit_price serving_size protein total_fat total_carb].freeze
  BOOLEANS = { "true" => true, "yes" => true, "1" => true, "false" => false, "no" => false, "0" => false }.freeze

  Row = Struct.new(:line, :name, :action, :ingredient, :attributes, :nutrition, :problems, :notes, keyword_init: true) do
    def invalid? = action == :invalid
    def create?  = action == :create
    def update?  = action == :update
  end

  class HeaderError < StandardError; end

  def initialize(path)
    @path = path
  end

  def rows
    @rows ||= plan
  end

  def apply!
    Ingredient.transaction do
      rows.each do |row|
        next unless row.create? || row.update?

        ingredient = row.ingredient || Ingredient.new(household: nil)
        ingredient.update!(row.attributes)
        next if row.nutrition.empty?

        fact = ingredient.nutrition_fact || ingredient.build_nutrition_fact
        fact.update!(row.nutrition)
      end
    end
  end

  private

  def plan
    table = CSV.read(@path, headers: true, encoding: "bom|utf-8")
    missing = COLUMNS - table.headers.compact.map { |header| header.strip.downcase }
    raise HeaderError, "missing columns: #{missing.join(', ')}" if missing.any?

    catalog = Ingredient.where(household_id: nil).includes(:nutrition_fact)
                        .index_by { |ingredient| Ingredient::NameAudit.same_ingredient_key(ingredient.ingredient, ingredient.brand) }
    seen = {}

    table.each.with_index(2).map do |csv_row, line|
      values = csv_row.to_h.transform_keys { |header| header.to_s.strip.downcase }
                      .transform_values { |value| value.to_s.strip.presence }
      plan_row(values, line, catalog, seen)
    end
  end

  def plan_row(values, line, catalog, seen)
    row = Row.new(line:, name: values["ingredient"], problems: [], notes: [], attributes: {}, nutrition: {})

    row.problems << "no ingredient name" if row.name.blank?
    ingredient_attributes(values, row)
    nutrition_attributes(values, row)

    key = Ingredient::NameAudit.same_ingredient_key(row.name, values["brand"])
    if row.name.present? && (earlier = seen[key])
      row.problems << "same ingredient as line #{earlier} — only the first is used"
    end
    seen[key] ||= line

    if row.problems.any?
      row.action = :invalid
    elsif (existing = catalog[key])
      row.ingredient = existing
      row.attributes = changed(existing, row.attributes)
      row.nutrition  = existing.nutrition_fact ? changed(existing.nutrition_fact, row.nutrition) : row.nutrition
      row.action = row.attributes.empty? && row.nutrition.empty? ? :unchanged : :update
    else
      row.action = :create
    end

    saved_name = Ingredient.new(ingredient: row.name).tap(&:validate).ingredient
    row.notes << "will be saved as \"#{saved_name}\"" if row.name.present? && saved_name != row.name && row.create?

    row
  end

  def ingredient_attributes(values, row)
    row.attributes["ingredient"] = row.name if row.name
    row.attributes["brand"] = values["brand"] if values["brand"]

    if (family = values["family"])
      FAMILIES.include?(family.downcase) ? row.attributes["family"] = family.downcase : row.problems << "family \"#{family}\" isn't one of #{FAMILIES.join(', ')}"
    end

    if (organic = values["organic"])
      BOOLEANS.key?(organic.downcase) ? row.attributes["organic"] = BOOLEANS[organic.downcase] : row.problems << "organic \"#{organic}\" isn't true or false"
    end

    %w[unit_price unit_servings].each { |column| number(values, column, row) { |value| row.attributes[column] = value } }
  end

  def nutrition_attributes(values, row)
    %w[serving_size calories protein total_fat total_carb].each { |column| number(values, column, row) { |value| row.nutrition[column] = value } }

    if (unit = values["serving_unit"])
      result = UnitNormalizer.call(unit)
      row.nutrition["serving_unit"] = result.unit
      row.notes.concat(result.notes)
    end

    given = NUTRITION_COLUMNS.any? { |column| values[column] }
    row.problems << "nutrition facts need a serving_size" if given && values["serving_size"].nil?
  end

  # Parses a numeric cell, yielding it when it's valid.
  def number(values, column, row)
    raw = values[column] or return
    cleaned = raw.delete(",$")

    if INTEGER_COLUMNS.include?(column)
      return row.problems << "#{column} \"#{raw}\" isn't a whole number" unless cleaned.match?(/\A\d+\z/)
      yield cleaned.to_i
    else
      return row.problems << "#{column} \"#{raw}\" isn't a number" unless cleaned.match?(/\A\d*\.?\d+\z/)
      yield cleaned.to_f
    end
  end

  # Only the values that would change the record (a blank never clears).
  def changed(record, attributes)
    attributes.reject { |attribute, value| attribute == "ingredient" || record[attribute] == value }
  end
end
