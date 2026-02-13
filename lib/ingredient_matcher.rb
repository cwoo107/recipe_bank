# lib/ingredient_matcher.rb
require 'fuzzy_match'

class IngredientMatcher
  def initialize
    @ingredients = Ingredient.all.to_a
  end

  def find_or_suggest(parsed_ingredient)
    search_name = parsed_ingredient[:search_name]
    original_name = parsed_ingredient[:name]

    # Try exact match first (case insensitive)
    exact = exact_match(search_name)
    return { match: exact, confidence: 1.0, method: 'exact' } if exact

    # Try partial match (e.g., "large chicken breasts" matches "chicken breasts")
    partial = partial_match(search_name)
    return { match: partial, confidence: 0.95, method: 'partial' } if partial

    # Try family match
    family = family_match(search_name)
    return { match: family, confidence: 0.85, method: 'family' } if family

    # Try fuzzy match
    fuzzy = fuzzy_match(search_name)
    if fuzzy
      confidence = calculate_confidence(search_name, fuzzy[:match].ingredient)
      if confidence > 0.75  # Raised threshold
        return { match: fuzzy[:match], confidence: confidence, method: 'fuzzy' }
      end
    end

    # No match
    {
      match: nil,
      confidence: 0.0,
      method: 'none',
      suggested_name: original_name
    }
  end

  private

  def exact_match(search_name)
    @ingredients.find do |ing|
      normalize(ing.ingredient) == search_name
    end
  end

  def partial_match(search_name)
    # Check if the search name contains an existing ingredient name
    # e.g., "large chicken breasts" contains "chicken breasts"
    @ingredients.find do |ing|
      ingredient_normalized = normalize(ing.ingredient)
      next if ingredient_normalized.empty?

      # Check both directions
      search_name.include?(ingredient_normalized) ||
        ingredient_normalized.include?(search_name)
    end
  end

  def family_match(search_name)
    # Look for family names in the search term
    @ingredients.find do |ing|
      next unless ing.family
      search_name.include?(normalize(ing.family))
    end
  end

  def fuzzy_match(search_name)
    # Use fuzzy matching gem
    fm = FuzzyMatch.new(@ingredients, read: :ingredient)
    match = fm.find(search_name)

    match ? { match: match } : nil
  end

  def calculate_confidence(str1, str2)
    str1 = normalize(str1)
    str2 = normalize(str2)

    # Levenshtein distance
    distance = levenshtein_distance(str1, str2)
    max_length = [str1.length, str2.length].max

    return 1.0 if max_length.zero?

    1.0 - (distance.to_f / max_length)
  end

  def levenshtein_distance(s, t)
    m = s.length
    n = t.length
    return m if n.zero?
    return n if m.zero?

    d = Array.new(m + 1) { Array.new(n + 1) }

    (0..m).each { |i| d[i][0] = i }
    (0..n).each { |j| d[0][j] = j }

    (1..n).each do |j|
      (1..m).each do |i|
        cost = s[i - 1] == t[j - 1] ? 0 : 1
        d[i][j] = [
          d[i - 1][j] + 1,      # deletion
          d[i][j - 1] + 1,      # insertion
          d[i - 1][j - 1] + cost # substitution
        ].min
      end
    end

    d[m][n]
  end

  def normalize(str)
    return '' unless str
    str.to_s.downcase
       .gsub(/\b(large|small|medium|fresh|frozen|dried|organic|whole|sliced|diced|chopped|minced|shredded|grated)\b/, '') # Remove descriptors
       .gsub(/[^a-z\s]/, '')
       .gsub(/\s+/, ' ')
       .strip
  end
end