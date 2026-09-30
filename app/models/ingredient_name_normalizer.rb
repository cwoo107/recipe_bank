# Cleans up an ingredient name that a recipe import mangled — leftover
# quantity fragments, units, prep words, "X or Y" alternatives — down to the
# ingredient itself:
#
#   IngredientNameNormalizer.call(". finely parmesan").name     # => "Parmesan"
#   IngredientNameNormalizer.call("/8 tsp black pepper").name   # => "Black pepper"
#   IngredientNameNormalizer.call("Vegetable or canola oil")    # => "Vegetable oil", with a note
#
# Returns a Result: the cleaned name (capitalized the way Ingredient saves
# names) and any notes worth a human's look — a quantity that was stuck in
# the name, an alternative that was dropped, two ingredients in one. Used by
# the ingredients:normalize_names audit (Ingredient::NameAudit) and, for new
# imports, IngredientParser#parse.
class IngredientNameNormalizer
  Result = Struct.new(:name, :notes, keyword_init: true) do
    def changed_from?(original) = name != original.to_s.strip.capitalize
  end

  UNITS = %w[
    tsp tsps teaspoon teaspoons tbsp tbsps tbs tablespoon tablespoons
    cup cups oz ounce ounces lb lbs pound pounds g gram grams kg ml l liter liters litre litres
    pinch pinches dash dashes can cans package packages pkg stick sticks
    quart quarts qt pint pints pt clove cloves sprig sprigs bunch bunches handful handfuls
  ].freeze

  # Prep and manner words the importer left behind ("finely", "freshly",
  # "torn") — they describe what to do, not what to buy. Deliberately not
  # here: words that change what you buy ("ground", "toasted", "crushed",
  # "smoked", "fresh", "dried").
  PREP_WORDS = %w[
    finely roughly coarsely thinly freshly lightly firmly loosely
    chopped minced diced sliced grated shredded torn softened melted beaten
    packed peeled halved quartered cubed rinsed drained divided sifted
  ].freeze

  # Herbs are bought as the herb, not its "leaves" or "sprigs" — except the
  # ones where the leaf is the product.
  KEEP_LEAVES_FOR = %w[bay curry lime kaffir].freeze

  # Dishes and products whose names really do contain "and".
  AND_IS_PART_OF_THE_NAME = [ "half and half", "macaroni and cheese", "mac and cheese", "salt and vinegar" ].freeze

  TRAILING_PHRASES = /\s+(?:to taste|as needed|for (?:garnish|garnishing|serving|frying|the pan|greasing)|divided|optional)\z/i
  SEE_REFERENCE    = /\Asee\s+(.+?)(?:\s+(?:alternative|alternatives|note|notes|below|above|recipe))?\z/i
  LEADING_JUNK     = %r{\A[\s.,;:/\-–—*•·\d½¼¾⅓⅔⅛⅜⅝⅞]+}
  LEADING_UNIT     = /\A(?:#{UNITS.join('|')})\.?\s+(?:of\s+)?(?=\S)/i
  PREP_WORD        = /(?<![\w-])(?:#{PREP_WORDS.join('|')})(?![\w-])/i # not inside "oil-packed"
  CUT_OFF_WORD     = /\b[a-z]+-(?=\s|\z)/i # "sun- tomatoes": the rest of "sun-dried" was lost
  ALTERNATIVES     = %r{\s*/\s*|\s+or\s+}i

  # capitalize: false keeps the name's own casing — for IngredientParser,
  # which hands lowercase names on to matching (Ingredient capitalizes on
  # save regardless).
  def self.call(name, capitalize: true) = new(name, capitalize:).call

  def initialize(name, capitalize: true)
    @original   = name.to_s
    @capitalize = capitalize
    @notes      = []
  end

  def call
    cleaned = @original.strip
    cleaned = cleaned.gsub(/\([^)]*\)/, " ")               # "(about 2 cups)"
    cleaned = cleaned.split(",").first.to_s                # "tomatoes, diced"
    cleaned = cleaned.sub(TRAILING_PHRASES, "")

    if (reference = cleaned.match(SEE_REFERENCE))
      cleaned = reference[1]
      note "was a cross-reference (\"#{@original.strip}\") — check the recipe says what it means"
    end

    cleaned = strip_leading_quantity(cleaned)
    cleaned = cleaned.gsub(PREP_WORD, " ")
    cleaned = cleaned.gsub(CUT_OFF_WORD) do |fragment|
      note "dropped a cut-off word (\"#{fragment}\") — the original may have been more specific"
      " "
    end
    cleaned = strip_leaves(squish(cleaned))
    cleaned = first_alternative(squish(cleaned))
    cleaned = squish(cleaned).gsub(/\A[^[:alnum:]]+|[^[:alnum:]]+\z/, "")

    flag_combined(cleaned)

    if cleaned.empty?
      note "couldn't be cleaned automatically — rename it by hand"
      cleaned = @original.strip
    end

    Result.new(name: @capitalize ? cleaned.capitalize : cleaned, notes: @notes)
  end

  private

  def note(message) = @notes << message

  def squish(string) = string.gsub(/\s+/, " ").strip

  # ". finely parmesan", "/8 tsp black pepper", "2 cups flour".
  def strip_leading_quantity(string)
    had_amount = false
    loop do
      before = string
      junk = string[LEADING_JUNK].to_s
      had_amount ||= junk.match?(%r{[\d/½¼¾⅓⅔⅛⅜⅝⅞]})
      string = string.sub(LEADING_JUNK, "")
      if string.match?(LEADING_UNIT)
        had_amount = true
        string = string.sub(LEADING_UNIT, "")
      end
      break if string == before
    end
    note "had an amount in its name — check the recipe line's quantity" if had_amount
    string
  end

  def strip_leaves(string)
    string.sub(/\s+(?:leaves|leaf|sprigs?)\z/i) do |suffix|
      head = string.delete_suffix(suffix)
      KEEP_LEAVES_FOR.include?(head.split.last.to_s.downcase) ? suffix : ""
    end
  end

  # "Caster sugar / superfine sugar" → "Caster sugar"; "Vegetable or canola
  # oil" → "Vegetable oil" (a lone first word borrows the shared noun).
  def first_alternative(string)
    first, *rest = string.split(ALTERNATIVES).map(&:strip).reject(&:empty?)
    return string if first.nil? || rest.empty?

    if first.split.size == 1 && rest.first.split.size > 1
      first = "#{first} #{rest.first.split.last}"
    end
    note "listed alternatives (\"#{string}\") — kept the first"
    first
  end

  def flag_combined(string)
    return unless string.match?(/\s(?:and|&|plus)\s/i)
    return if AND_IS_PART_OF_THE_NAME.any? { |name| string.downcase.include?(name) }

    note "looks like two ingredients in one — split it into separate recipe lines by hand"
  end
end
