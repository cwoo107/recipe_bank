# After the grocery list is generated: which of the week's ingredients look
# like something waiting on the restock list, for the user to confirm
# (RestockMatchesController). Pairs they've already answered — yes or no —
# are left out, so each is only asked about once (RestockItemIngredient).
#
# Names match when one is the other's words, give or take more words around
# them and plurals: "Olive oil" and "Extra virgin olive oil", "Eggs" and
# "Large egg". Whole words only, so "Salt" isn't "Salted butter".
class RestockMatch
  Suggestion = Struct.new(:ingredient, :restock_item, keyword_init: true) do
    # What the review form posts back for this pair.
    def key = "#{restock_item.id}-#{ingredient.id}"
  end

  def self.suggestions(household, week_start)
    ingredients = Ingredient.where(
      id: household.grocery_lists.where(week_of: week_start...(week_start + 7)).where.not(ingredient_id: nil).select(:ingredient_id)
    ).order(:ingredient).to_a
    items = household.restock_items.where(restock: true).order(:name).to_a
    return [] if ingredients.empty? || items.empty?

    answered = RestockItemIngredient.where(restock_item_id: items.map(&:id), ingredient_id: ingredients.map(&:id))
                                    .pluck(:restock_item_id, :ingredient_id).to_set

    ingredients.flat_map do |ingredient|
      items.filter_map do |item|
        next if answered.include?([ item.id, ingredient.id ])
        Suggestion.new(ingredient:, restock_item: item) if same_thing?(ingredient.ingredient, item.name)
      end
    end
  end

  def self.same_thing?(a, b)
    shorter, longer = [ words(a), words(b) ].sort_by(&:size)
    shorter.any? && longer.each_cons(shorter.size).include?(shorter)
  end

  def self.words(name)
    IngredientParser.normalize_for_search(name).split.map(&:singularize)
  end
  private_class_method :words
end
