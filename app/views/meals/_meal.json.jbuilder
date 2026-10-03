json.extract! meal, :id, :recipe_id, :note, :meal_name, :date, :created_at, :updated_at
json.url meal_url(meal, format: :json)
