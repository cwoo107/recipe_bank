json.extract! recipe_ingredient, :id, :recipe_id, :ingredient_id, :unit, :quantity, :created_at, :updated_at
json.url recipe_ingredient_url(recipe_ingredient, format: :json)
