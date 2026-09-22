# Stands in for Ollama so the importer's AI steps stay offline and
# deterministic. Answers have the same shape the real client returns;
# resolve_ingredients declines to add any matches of its own.
class FakeOllamaAssistant
  def resolve_ingredients(_entries) = []

  def classify_ingredient_families(ingredients)
    ingredients.map { |i| { "name" => i[:name], "family" => "produce" } }
  end

  def estimate_nutrition_facts(ingredients)
    ingredients.map { |i| fallback_nutrition_estimate(i[:name], i[:family]) }
  end

  def guess_family_programmatically(_name) = "produce"

  def fallback_nutrition_estimate(name, _family)
    { calories: 10, protein: 1, total_fat: 0, total_carb: 2,
      serving_size: 1, serving_unit: "cup", unit_price: 1.5, unit_servings: 4,
      name: name }
  end
end
