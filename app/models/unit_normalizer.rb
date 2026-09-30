# Maps however a unit was written — "Tbsp", "tablespoons", "T", "grams",
# "fl. oz." — to the one spelling the recipe page's unit picker uses
# (RecipeIngredient::UNITS):
#
#   UnitNormalizer.call("Tablespoons").unit  # => "tbsp"
#   UnitNormalizer.call("T").unit            # => "tbsp"  (capital T)
#   UnitNormalizer.call("t").unit            # => "tsp"   (small t)
#   UnitNormalizer.call("whole").unit        # => nil     (a count: "3 eggs")
#   UnitNormalizer.call("can")               # => "can", with a note
#
# Returns a Result: the unit to store (nil for none) and any notes worth a
# human's look — a unit that isn't one of the picker's is left as it is.
# Used when recipe lines and nutrition facts are saved, and by the
# ingredients:normalize_units audit (UnitAudit).
class UnitNormalizer
  Result = Struct.new(:unit, :notes, keyword_init: true) do
    def changed_from?(original) = unit != original.presence
    def recognized? = notes.empty?
  end

  # Every picker unit, and the other ways people write it (compared
  # lowercased, without trailing dots or extra spaces).
  ALIASES = {
    "tsp"    => %w[tsp tsps teaspoon teaspoons],
    "tbsp"   => %w[tbsp tbsps tbs tbl tbls tablespoon tablespoons],
    "fl oz"  => [ "fl oz", "fl. oz", "floz", "fluid ounce", "fluid ounces", "fl ounce", "fl ounces" ],
    "cup"    => %w[cup cups],
    "pint"   => %w[pint pints pt pts],
    "quart"  => %w[quart quarts qt qts],
    "ml"     => %w[ml mls milliliter milliliters millilitre millilitres],
    "liter"  => %w[l liter liters litre litres],
    "oz"     => %w[oz ounce ounces],
    "lb"     => %w[lb lbs pound pounds],
    "g"      => %w[g gs gr gram grams gramme grammes],
    "kg"     => %w[kg kgs kilo kilos kilogram kilograms],
    "piece"  => %w[piece pieces pc pcs],
    "slice"  => %w[slice slices],
    "clove"  => %w[clove cloves],
    "pinch"  => %w[pinch pinches],
    "dash"   => %w[dash dashes]
  }.freeze

  # Words that just mean "this many of it" — stored as no unit, the app's
  # way of writing a count ("1 chicken breast"), which weighs the same as a
  # piece.
  COUNT_WORDS = %w[whole each ea item items unit units count].freeze

  LOOKUP = ALIASES.flat_map { |unit, spellings| spellings.map { |spelling| [ spelling, unit ] } }.to_h.freeze

  def self.call(unit) = new(unit).call

  def initialize(unit)
    @original = unit.to_s
  end

  def call
    written = @original.squish.delete_suffix(".").strip
    return Result.new(unit: nil, notes: []) if written.empty?

    # Recipe shorthand: capital T is a tablespoon, small t a teaspoon.
    return Result.new(unit: "tbsp", notes: []) if written == "T"
    return Result.new(unit: "tsp", notes: []) if written == "t"

    key = written.downcase.gsub(/\s*\.\s*/, " ").squish # "fl. oz." → "fl oz"
    return Result.new(unit: LOOKUP[key], notes: []) if LOOKUP.key?(key)
    return Result.new(unit: nil, notes: []) if COUNT_WORDS.include?(key)

    Result.new(unit: @original.strip, notes: [ "\"#{@original.strip}\" isn't one of the recipe page's units — left as is" ])
  end
end
