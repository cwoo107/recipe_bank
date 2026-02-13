# db/seeds.rb

puts "Clearing existing data..."
RecipeTag.destroy_all
RecipeIngredient.destroy_all
Step.destroy_all
Recipe.destroy_all
NutritionFact.destroy_all
IngredientTag.destroy_all
Ingredient.destroy_all
Tag.destroy_all

puts "Creating tags..."
tags = {
  breakfast: Tag.create!(tag: "Breakfast", color: "#d4b157"),      # Honey yellow (darker)
  lunch: Tag.create!(tag: "Lunch", color: "#7a9d9d"),              # Seafoam teal (darker)
  dinner: Tag.create!(tag: "Dinner", color: "#577584"),            # Mist blue (darker)
  dessert: Tag.create!(tag: "Dessert", color: "#a67a7f"),          # Rose pink (darker)
  vegetarian: Tag.create!(tag: "Vegetarian", color: "#7a8f62"),    # Sage green (darker)
  gluten_free: Tag.create!(tag: "Gluten Free", color: "#d4b157"),  # Honey yellow (darker)
  quick: Tag.create!(tag: "Quick & Easy", color: "#7a9d9d"),       # Seafoam (darker)
  healthy: Tag.create!(tag: "Healthy", color: "#7a8f62"),          # Sage (darker)
  comfort: Tag.create!(tag: "Comfort Food", color: "#b5806a"),     # Terracotta (darker)
  bbq: Tag.create!(tag: "BBQ & Grilling", color: "#a67a7f")        # Rose (darker)
}

puts "Creating ingredients with nutrition facts..."

# Proteins
chicken_breast = Ingredient.create!(
  ingredient: "Chicken Breast",
  family: "protein",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: chicken_breast,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 3.6,
  total_carb: 0,
  protein: 31,
  calories: 160
)

salmon = Ingredient.create!(
  ingredient: "Salmon Fillet",
  family: "protein",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: salmon,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 13,
  total_carb: 0,
  protein: 20,
  calories: 210
)

eggs = Ingredient.create!(
  ingredient: "Large Eggs",
  family: "protein",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: eggs,
  serving_size: 50,
  serving_unit: "g",
  total_fat: 5,
  total_carb: 0.6,
  protein: 6,
  calories: 70
)

ground_beef = Ingredient.create!(
  ingredient: "Ground Beef",
  family: "protein",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: ground_beef,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 15,
  total_carb: 0,
  protein: 26,
  calories: 250
)

bacon = Ingredient.create!(
  ingredient: "Bacon",
  family: "protein",
  brand: "Wright Brand",
  organic: false
)
NutritionFact.create!(
  ingredient: bacon,
  serving_size: 28,
  serving_unit: "g",
  total_fat: 12,
  total_carb: 0.4,
  protein: 9,
  calories: 140
)

pork_chops = Ingredient.create!(
  ingredient: "Pork Chops",
  family: "protein",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: pork_chops,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 7,
  total_carb: 0,
  protein: 26,
  calories: 170
)

shrimp = Ingredient.create!(
  ingredient: "Large Shrimp",
  family: "protein",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: shrimp,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 0.2,
  protein: 24,
  calories: 100
)

# Vegetables
spinach = Ingredient.create!(
  ingredient: "Fresh Spinach",
  family: "vegetable",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: spinach,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.4,
  total_carb: 3.6,
  protein: 2.9,
  calories: 20
)

broccoli = Ingredient.create!(
  ingredient: "Broccoli",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: broccoli,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.4,
  total_carb: 6.6,
  protein: 2.8,
  calories: 30
)

bell_pepper = Ingredient.create!(
  ingredient: "Red Bell Pepper",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: bell_pepper,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 6,
  protein: 1,
  calories: 30
)

tomatoes = Ingredient.create!(
  ingredient: "Roma Tomatoes",
  family: "vegetable",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: tomatoes,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.2,
  total_carb: 3.9,
  protein: 0.9,
  calories: 20
)

garlic = Ingredient.create!(
  ingredient: "Fresh Garlic",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: garlic,
  serving_size: 10,
  serving_unit: "g",
  total_fat: 0.1,
  total_carb: 3.3,
  protein: 0.6,
  calories: 10
)

onion = Ingredient.create!(
  ingredient: "Yellow Onion",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: onion,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.1,
  total_carb: 9.3,
  protein: 1.1,
  calories: 40
)

mushrooms = Ingredient.create!(
  ingredient: "Button Mushrooms",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: mushrooms,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 3.3,
  protein: 3.1,
  calories: 20
)

potatoes = Ingredient.create!(
  ingredient: "Russet Potatoes",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: potatoes,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.1,
  total_carb: 17,
  protein: 2,
  calories: 80
)

asparagus = Ingredient.create!(
  ingredient: "Asparagus",
  family: "vegetable",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: asparagus,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.1,
  total_carb: 3.9,
  protein: 2.2,
  calories: 20
)

# Fruits
banana = Ingredient.create!(
  ingredient: "Banana",
  family: "fruit",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: banana,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 22.8,
  protein: 1.1,
  calories: 90
)

blueberries = Ingredient.create!(
  ingredient: "Fresh Blueberries",
  family: "fruit",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: blueberries,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 14.5,
  protein: 0.7,
  calories: 60
)

strawberries = Ingredient.create!(
  ingredient: "Fresh Strawberries",
  family: "fruit",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: strawberries,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.3,
  total_carb: 7.7,
  protein: 0.7,
  calories: 30
)

lemon = Ingredient.create!(
  ingredient: "Lemon",
  family: "fruit",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: lemon,
  serving_size: 58,
  serving_unit: "g",
  total_fat: 0.2,
  total_carb: 5.4,
  protein: 0.6,
  calories: 20
)

# Grains
rice = Ingredient.create!(
  ingredient: "Basmati Rice",
  family: "grain",
  brand: "Royal",
  organic: false
)
NutritionFact.create!(
  ingredient: rice,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 0.4,
  total_carb: 25,
  protein: 2.7,
  calories: 110
)

quinoa = Ingredient.create!(
  ingredient: "Quinoa",
  family: "grain",
  brand: "Bob's Red Mill",
  organic: true
)
NutritionFact.create!(
  ingredient: quinoa,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 1.9,
  total_carb: 21.3,
  protein: 4.4,
  calories: 120
)

oats = Ingredient.create!(
  ingredient: "Rolled Oats",
  family: "grain",
  brand: "Quaker",
  organic: false
)
NutritionFact.create!(
  ingredient: oats,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 6.9,
  total_carb: 66.3,
  protein: 16.9,
  calories: 390
)

flour = Ingredient.create!(
  ingredient: "All-Purpose Flour",
  family: "grain",
  brand: "King Arthur",
  organic: false
)
NutritionFact.create!(
  ingredient: flour,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 1,
  total_carb: 76,
  protein: 10,
  calories: 360
)

pasta = Ingredient.create!(
  ingredient: "Penne Pasta",
  family: "grain",
  brand: "Barilla",
  organic: false
)
NutritionFact.create!(
  ingredient: pasta,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 1.5,
  total_carb: 75,
  protein: 13,
  calories: 370
)

bread = Ingredient.create!(
  ingredient: "Sourdough Bread",
  family: "grain",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: bread,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 1,
  total_carb: 52,
  protein: 8,
  calories: 260
)

# Fats
olive_oil = Ingredient.create!(
  ingredient: "Extra Virgin Olive Oil",
  family: "fat",
  brand: "Bertolli",
  organic: false
)
NutritionFact.create!(
  ingredient: olive_oil,
  serving_size: 14,
  serving_unit: "g",
  total_fat: 14,
  total_carb: 0,
  protein: 0,
  calories: 120
)

butter = Ingredient.create!(
  ingredient: "Unsalted Butter",
  family: "fat",
  brand: "Land O'Lakes",
  organic: false
)
NutritionFact.create!(
  ingredient: butter,
  serving_size: 14,
  serving_unit: "g",
  total_fat: 11.5,
  total_carb: 0.1,
  protein: 0.1,
  calories: 100
)

avocado = Ingredient.create!(
  ingredient: "Avocado",
  family: "fat",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: avocado,
  serving_size: 100,
  serving_unit: "g",
  total_fat: 14.7,
  total_carb: 8.5,
  protein: 2,
  calories: 160
)

# Dairy & Other
milk = Ingredient.create!(
  ingredient: "Whole Milk",
  family: "protein",
  brand: "Organic Valley",
  organic: true
)
NutritionFact.create!(
  ingredient: milk,
  serving_size: 240,
  serving_unit: "ml",
  total_fat: 8,
  total_carb: 12,
  protein: 8,
  calories: 150
)

cheese = Ingredient.create!(
  ingredient: "Parmesan Cheese",
  family: "protein",
  brand: "Kraft",
  organic: false
)
NutritionFact.create!(
  ingredient: cheese,
  serving_size: 28,
  serving_unit: "g",
  total_fat: 7.3,
  total_carb: 0.9,
  protein: 10,
  calories: 110
)

cheddar = Ingredient.create!(
  ingredient: "Sharp Cheddar Cheese",
  family: "protein",
  brand: "Tillamook",
  organic: false
)
NutritionFact.create!(
  ingredient: cheddar,
  serving_size: 28,
  serving_unit: "g",
  total_fat: 9,
  total_carb: 0.4,
  protein: 7,
  calories: 110
)

cream = Ingredient.create!(
  ingredient: "Heavy Cream",
  family: "fat",
  brand: nil,
  organic: false
)
NutritionFact.create!(
  ingredient: cream,
  serving_size: 15,
  serving_unit: "ml",
  total_fat: 5.5,
  total_carb: 0.4,
  protein: 0.3,
  calories: 50
)

honey = Ingredient.create!(
  ingredient: "Raw Honey",
  family: "fruit",
  brand: nil,
  organic: true
)
NutritionFact.create!(
  ingredient: honey,
  serving_size: 21,
  serving_unit: "g",
  total_fat: 0,
  total_carb: 17,
  protein: 0.1,
  calories: 60
)

soy_sauce = Ingredient.create!(
  ingredient: "Soy Sauce",
  family: "protein",
  brand: "Kikkoman",
  organic: false
)

ginger = Ingredient.create!(
  ingredient: "Fresh Ginger",
  family: "vegetable",
  brand: nil,
  organic: false
)

maple_syrup = Ingredient.create!(
  ingredient: "Pure Maple Syrup",
  family: "fruit",
  brand: nil,
  organic: false
)

vanilla = Ingredient.create!(
  ingredient: "Vanilla Extract",
  family: "fruit",
  brand: "McCormick",
  organic: false
)

sugar = Ingredient.create!(
  ingredient: "Granulated Sugar",
  family: "fruit",
  brand: "Domino",
  organic: false
)

baking_powder = Ingredient.create!(
  ingredient: "Baking Powder",
  family: "grain",
  brand: "Clabber Girl",
  organic: false
)

puts "Creating recipes..."

# Recipe 1: Grilled Chicken with Quinoa
recipe1 = Recipe.create!(
  title: "Grilled Lemon Herb Chicken with Quinoa",
  description: "A healthy and flavorful dinner featuring perfectly grilled chicken breast served over fluffy quinoa with roasted vegetables.",
  servings: 2
)
recipe1.tags << [tags[:dinner], tags[:healthy], tags[:gluten_free]]

RecipeIngredient.create!(recipe: recipe1, ingredient: chicken_breast, quantity: 170, unit: "g")
RecipeIngredient.create!(recipe: recipe1, ingredient: quinoa, quantity: 185, unit: "g")
RecipeIngredient.create!(recipe: recipe1, ingredient: broccoli, quantity: 150, unit: "g")
RecipeIngredient.create!(recipe: recipe1, ingredient: olive_oil, quantity: 30, unit: "ml")
RecipeIngredient.create!(recipe: recipe1, ingredient: lemon, quantity: 1, unit: "whole")
RecipeIngredient.create!(recipe: recipe1, ingredient: garlic, quantity: 3, unit: "cloves")

Step.create!(recipe: recipe1, position: 1, content: "Rinse quinoa under cold water. In a medium pot, combine 1 cup quinoa with 2 cups water. Bring to a boil, then reduce heat to low, cover, and simmer for 15 minutes.")
Step.create!(recipe: recipe1, position: 2, content: "While quinoa cooks, season chicken breasts with salt, pepper, and minced garlic. Drizzle with olive oil and lemon juice.")
Step.create!(recipe: recipe1, position: 3, content: "Heat grill or grill pan to medium-high heat. Grill chicken for 6-7 minutes per side until internal temperature reaches 165°F.")
Step.create!(recipe: recipe1, position: 4, content: "Steam broccoli florets for 5 minutes until tender-crisp. Toss with a drizzle of olive oil.")
Step.create!(recipe: recipe1, position: 5, content: "Fluff quinoa with a fork. Serve chicken over quinoa with steamed broccoli on the side. Garnish with fresh lemon wedges.")

# Recipe 2: Classic Cheeseburgers
recipe2 = Recipe.create!(
  title: "Classic Homemade Cheeseburgers",
  description: "Juicy beef patties topped with melted cheddar cheese, fresh vegetables, and served on toasted buns. A family favorite!",
  servings: 4
)
recipe2.tags << [tags[:dinner], tags[:comfort], tags[:bbq]]

RecipeIngredient.create!(recipe: recipe2, ingredient: ground_beef, quantity: 450, unit: "g")
RecipeIngredient.create!(recipe: recipe2, ingredient: cheddar, quantity: 112, unit: "g")
RecipeIngredient.create!(recipe: recipe2, ingredient: bread, quantity: 200, unit: "g")
RecipeIngredient.create!(recipe: recipe2, ingredient: tomatoes, quantity: 1, unit: "whole")
RecipeIngredient.create!(recipe: recipe2, ingredient: onion, quantity: 0.5, unit: "whole")
RecipeIngredient.create!(recipe: recipe2, ingredient: olive_oil, quantity: 15, unit: "ml")

Step.create!(recipe: recipe2, position: 1, content: "Divide ground beef into 4 equal portions and form into patties about 3/4 inch thick. Make a small indent in the center of each patty to prevent bulging during cooking.")
Step.create!(recipe: recipe2, position: 2, content: "Season both sides of patties generously with salt and pepper. Heat a cast iron skillet or grill to medium-high heat.")
Step.create!(recipe: recipe2, position: 3, content: "Cook patties for 4 minutes on first side without moving them. Flip and cook for another 3-4 minutes.")
Step.create!(recipe: recipe2, position: 4, content: "Place a slice of cheddar on each patty during the last minute of cooking. Cover with a lid to help cheese melt.")
Step.create!(recipe: recipe2, position: 5, content: "Toast buns lightly. Slice tomatoes and onions. Assemble burgers with your favorite condiments and serve immediately.")

# Recipe 3: Honey Teriyaki Salmon
recipe3 = Recipe.create!(
  title: "Honey Teriyaki Glazed Salmon",
  description: "Succulent salmon fillets glazed with a sweet and savory teriyaki sauce, served with steamed rice and crisp vegetables.",
  servings: 2
)
recipe3.tags << [tags[:dinner], tags[:healthy], tags[:quick]]

RecipeIngredient.create!(recipe: recipe3, ingredient: salmon, quantity: 170, unit: "g")
RecipeIngredient.create!(recipe: recipe3, ingredient: rice, quantity: 185, unit: "g")
RecipeIngredient.create!(recipe: recipe3, ingredient: soy_sauce, quantity: 45, unit: "ml")
RecipeIngredient.create!(recipe: recipe3, ingredient: honey, quantity: 42, unit: "g")
RecipeIngredient.create!(recipe: recipe3, ingredient: ginger, quantity: 15, unit: "g")
RecipeIngredient.create!(recipe: recipe3, ingredient: garlic, quantity: 2, unit: "cloves")
RecipeIngredient.create!(recipe: recipe3, ingredient: broccoli, quantity: 150, unit: "g")

Step.create!(recipe: recipe3, position: 1, content: "Cook rice according to package directions. In a small bowl, whisk together soy sauce, honey, minced ginger, and minced garlic.")
Step.create!(recipe: recipe3, position: 2, content: "Pat salmon fillets dry and season lightly with salt and pepper. Heat a non-stick pan over medium-high heat with a bit of oil.")
Step.create!(recipe: recipe3, position: 3, content: "Place salmon skin-side up in the pan. Cook for 4 minutes, then flip and cook for another 3-4 minutes.")
Step.create!(recipe: recipe3, position: 4, content: "Pour the teriyaki sauce over the salmon and let it simmer for 1-2 minutes, spooning sauce over the fish as it glazes.")
Step.create!(recipe: recipe3, position: 5, content: "Steam broccoli for 5 minutes. Serve salmon over rice with broccoli on the side, drizzling extra teriyaki sauce over everything.")

# Recipe 4: Breakfast Scramble
recipe4 = Recipe.create!(
  title: "Classic Bacon and Egg Breakfast",
  description: "Start your day right with crispy bacon, fluffy scrambled eggs, and golden toast. A hearty breakfast classic.",
  servings: 1
)
recipe4.tags << [tags[:breakfast], tags[:quick], tags[:comfort]]

RecipeIngredient.create!(recipe: recipe4, ingredient: eggs, quantity: 3, unit: "whole")
RecipeIngredient.create!(recipe: recipe4, ingredient: bacon, quantity: 4, unit: "strips")
RecipeIngredient.create!(recipe: recipe4, ingredient: butter, quantity: 14, unit: "g")
RecipeIngredient.create!(recipe: recipe4, ingredient: milk, quantity: 30, unit: "ml")
RecipeIngredient.create!(recipe: recipe4, ingredient: bread, quantity: 2, unit: "slices")
RecipeIngredient.create!(recipe: recipe4, ingredient: cheddar, quantity: 28, unit: "g")

Step.create!(recipe: recipe4, position: 1, content: "Cook bacon in a large skillet over medium heat until crispy, about 8-10 minutes. Remove and drain on paper towels.")
Step.create!(recipe: recipe4, position: 2, content: "While bacon cooks, whisk eggs with milk, salt, and pepper in a bowl until well combined.")
Step.create!(recipe: recipe4, position: 3, content: "Melt butter in a non-stick skillet over medium-low heat. Pour in eggs and let sit for 30 seconds.")
Step.create!(recipe: recipe4, position: 4, content: "Gently push eggs from edges to center with a spatula, allowing uncooked egg to flow to the bottom. When almost set but still slightly creamy, remove from heat.")
Step.create!(recipe: recipe4, position: 5, content: "Sprinkle shredded cheddar over eggs. Toast bread until golden. Serve eggs with bacon and toast on the side.")

# Recipe 5: Garlic Butter Shrimp Pasta
recipe5 = Recipe.create!(
  title: "Garlic Butter Shrimp Pasta",
  description: "Succulent shrimp tossed with pasta in a rich garlic butter sauce with fresh herbs. Restaurant-quality in 20 minutes!",
  servings: 4
)
recipe5.tags << [tags[:dinner], tags[:quick]]

RecipeIngredient.create!(recipe: recipe5, ingredient: shrimp, quantity: 450, unit: "g")
RecipeIngredient.create!(recipe: recipe5, ingredient: pasta, quantity: 340, unit: "g")
RecipeIngredient.create!(recipe: recipe5, ingredient: butter, quantity: 56, unit: "g")
RecipeIngredient.create!(recipe: recipe5, ingredient: garlic, quantity: 6, unit: "cloves")
RecipeIngredient.create!(recipe: recipe5, ingredient: lemon, quantity: 1, unit: "whole")
RecipeIngredient.create!(recipe: recipe5, ingredient: cheese, quantity: 56, unit: "g")
RecipeIngredient.create!(recipe: recipe5, ingredient: spinach, quantity: 100, unit: "g")

Step.create!(recipe: recipe5, position: 1, content: "Bring a large pot of salted water to boil. Cook pasta according to package directions until al dente. Reserve 1 cup pasta water before draining.")
Step.create!(recipe: recipe5, position: 2, content: "While pasta cooks, pat shrimp dry and season with salt and pepper. Mince garlic cloves.")
Step.create!(recipe: recipe5, position: 3, content: "Melt 2 tablespoons butter in a large skillet over medium-high heat. Add shrimp and cook for 2 minutes per side until pink and cooked through. Remove and set aside.")
Step.create!(recipe: recipe5, position: 4, content: "In the same skillet, melt remaining butter. Add garlic and cook for 1 minute until fragrant. Add spinach and cook until wilted.")
Step.create!(recipe: recipe5, position: 5, content: "Add cooked pasta, shrimp, lemon juice, and a splash of pasta water to the skillet. Toss everything together. Top with Parmesan and serve immediately.")

# Recipe 6: Pork Chops with Mushrooms
recipe6 = Recipe.create!(
  title: "Pan-Seared Pork Chops with Mushroom Sauce",
  description: "Juicy pork chops with a creamy mushroom sauce. A comforting dinner that's elegant enough for guests.",
  servings: 4
)
recipe6.tags << [tags[:dinner], tags[:comfort]]

RecipeIngredient.create!(recipe: recipe6, ingredient: pork_chops, quantity: 400, unit: "g")
RecipeIngredient.create!(recipe: recipe6, ingredient: mushrooms, quantity: 225, unit: "g")
RecipeIngredient.create!(recipe: recipe6, ingredient: cream, quantity: 120, unit: "ml")
RecipeIngredient.create!(recipe: recipe6, ingredient: butter, quantity: 28, unit: "g")
RecipeIngredient.create!(recipe: recipe6, ingredient: garlic, quantity: 3, unit: "cloves")
RecipeIngredient.create!(recipe: recipe6, ingredient: onion, quantity: 0.5, unit: "whole")

Step.create!(recipe: recipe6, position: 1, content: "Pat pork chops dry and season generously with salt and pepper on both sides.")
Step.create!(recipe: recipe6, position: 2, content: "Heat 1 tablespoon butter in a large skillet over medium-high heat. Add pork chops and cook for 4-5 minutes per side until golden brown and cooked through. Remove and tent with foil.")
Step.create!(recipe: recipe6, position: 3, content: "In the same skillet, add remaining butter. Sauté sliced mushrooms and diced onions for 5-6 minutes until browned.")
Step.create!(recipe: recipe6, position: 4, content: "Add minced garlic and cook for 30 seconds. Pour in heavy cream and bring to a simmer. Cook for 2-3 minutes until slightly thickened. Season with salt and pepper.")
Step.create!(recipe: recipe6, position: 5, content: "Return pork chops to the skillet and spoon mushroom sauce over them. Simmer for 1-2 minutes to reheat. Serve with mashed potatoes or rice.")

# Recipe 7: Blueberry Pancakes
recipe7 = Recipe.create!(
  title: "Fluffy Blueberry Pancakes",
  description: "Light and airy pancakes studded with fresh blueberries. Perfect weekend breakfast treat!",
  servings: 4
)
recipe7.tags << [tags[:breakfast], tags[:comfort]]

RecipeIngredient.create!(recipe: recipe7, ingredient: flour, quantity: 240, unit: "g")
RecipeIngredient.create!(recipe: recipe7, ingredient: milk, quantity: 360, unit: "ml")
RecipeIngredient.create!(recipe: recipe7, ingredient: eggs, quantity: 2, unit: "whole")
RecipeIngredient.create!(recipe: recipe7, ingredient: butter, quantity: 42, unit: "g")
RecipeIngredient.create!(recipe: recipe7, ingredient: sugar, quantity: 25, unit: "g")
RecipeIngredient.create!(recipe: recipe7, ingredient: baking_powder, quantity: 10, unit: "g")
RecipeIngredient.create!(recipe: recipe7, ingredient: blueberries, quantity: 150, unit: "g")
RecipeIngredient.create!(recipe: recipe7, ingredient: maple_syrup, quantity: 60, unit: "ml")

Step.create!(recipe: recipe7, position: 1, content: "In a large bowl, whisk together flour, sugar, baking powder, and a pinch of salt.")
Step.create!(recipe: recipe7, position: 2, content: "In another bowl, whisk together milk, eggs, and 2 tablespoons melted butter.")
Step.create!(recipe: recipe7, position: 3, content: "Pour wet ingredients into dry ingredients and stir until just combined. Don't overmix – a few lumps are fine. Gently fold in blueberries.")
Step.create!(recipe: recipe7, position: 4, content: "Heat a griddle or non-stick pan over medium heat. Brush with remaining butter. Pour 1/4 cup batter for each pancake.")
Step.create!(recipe: recipe7, position: 5, content: "Cook until bubbles form on surface and edges look set, about 2-3 minutes. Flip and cook another 2 minutes until golden. Serve hot with maple syrup and extra blueberries.")

# Recipe 8: Grilled Steak with Roasted Potatoes
recipe8 = Recipe.create!(
  title: "Grilled Ribeye with Garlic Herb Roasted Potatoes",
  description: "A classic steakhouse dinner at home. Perfectly grilled steak with crispy roasted potatoes and asparagus.",
  servings: 2
)
recipe8.tags << [tags[:dinner], tags[:bbq], tags[:comfort]]

RecipeIngredient.create!(recipe: recipe8, ingredient: ground_beef, quantity: 450, unit: "g")
RecipeIngredient.create!(recipe: recipe8, ingredient: potatoes, quantity: 680, unit: "g")
RecipeIngredient.create!(recipe: recipe8, ingredient: asparagus, quantity: 450, unit: "g")
RecipeIngredient.create!(recipe: recipe8, ingredient: garlic, quantity: 4, unit: "cloves")
RecipeIngredient.create!(recipe: recipe8, ingredient: olive_oil, quantity: 60, unit: "ml")
RecipeIngredient.create!(recipe: recipe8, ingredient: butter, quantity: 28, unit: "g")

Step.create!(recipe: recipe8, position: 1, content: "Preheat oven to 425°F. Cut potatoes into 1-inch cubes and toss with 2 tablespoons olive oil, minced garlic, salt, and pepper. Spread on a baking sheet and roast for 30-35 minutes, stirring halfway through.")
Step.create!(recipe: recipe8, position: 2, content: "Let steak come to room temperature for 30 minutes. Pat dry and season generously with salt and pepper on both sides.")
Step.create!(recipe: recipe8, position: 3, content: "Heat a cast iron skillet or grill to high heat. Add 1 tablespoon olive oil. Sear steak for 4-5 minutes per side for medium-rare, or longer for desired doneness.")
Step.create!(recipe: recipe8, position: 4, content: "Remove steak from heat and top with butter. Let rest for 5-10 minutes before slicing.")
Step.create!(recipe: recipe8, position: 5, content: "While steak rests, trim asparagus and toss with remaining olive oil, salt, and pepper. Roast for 10-12 minutes until tender. Serve steak sliced with potatoes and asparagus.")

puts "✅ Seed data created successfully!"
puts "   - #{Ingredient.count} ingredients"
puts "   - #{NutritionFact.count} nutrition facts"
puts "   - #{Tag.count} tags"
puts "   - #{Recipe.count} recipes"
puts "   - #{RecipeIngredient.count} recipe ingredients"
puts "   - #{Step.count} recipe steps"