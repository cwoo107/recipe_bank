json.extract! grocery_list, :id, :week_of, :ingredient_id, :meal_id, :units, :checked, :manually_adjusted, :created_at, :updated_at
json.url grocery_list_url(grocery_list, format: :json)
