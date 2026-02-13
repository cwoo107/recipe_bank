json.extract! nutrition_fact, :id, :ingredient_id, :serving_unit, :serving_size, :total_fat, :total_carb, :protein, :created_at, :updated_at
json.url nutrition_fact_url(nutrition_fact, format: :json)
