module MealsHelper
  def meal_grid_position(meal, week_start_date)
    # Calculate row (1-7 based on day of week)
    days_from_start = (meal.date - week_start_date).to_i
    row = days_from_start + 1

    # Calculate column based on meal_name (2=breakfast, 3=lunch, 4=dinner)
    column = case meal.meal_name.downcase
             when "breakfast" then 2
             when "lunch" then 3
             when "dinner" then 4
             else 2 # default to breakfast column
             end

    "grid-row: #{row} / span 1; grid-column: #{column} / span 1"
  end

  def meal_color_classes(meal)
    case meal.meal_name.downcase
    when "breakfast"
      {
        bg: "bg-honey-300",
        hover: "hover:bg-honey-400",
        ring: "inset-ring-honey-600/20",
        dark_bg: "dark:bg-honey-800/20",
        dark_ring: "dark:inset-ring-honey-300/30",
        title: "text-honey-800 dark:text-honey-300",
        subtitle: "text-honey-700 dark:text-honey-400"
      }
    when "lunch"
      {
        bg: "bg-seafoam-300",
        hover: "hover:bg-seafoam-400",
        ring: "inset-ring-seafoam-600/20",
        dark_bg: "dark:bg-seafoam-800/20",
        dark_ring: "dark:inset-ring-seafoam-300/30",
        title: "text-seafoam-800 dark:text-seafoam-300",
        subtitle: "text-seafoam-700 dark:text-seafoam-400"
      }
    when "dinner"
      {
        bg: "bg-mist-300",
        hover: "hover:bg-mist-400",
        ring: "inset-ring-mist-600/20",
        dark_bg: "dark:bg-mist-800/20",
        dark_ring: "dark:inset-ring-mist-300/30",
        title: "text-mist-800 dark:text-mist-300",
        subtitle: "text-mist-700 dark:text-mist-400"
      }
    else
      # Default to breakfast colors
      {
        bg: "bg-honey-300",
        hover: "hover:bg-honey-400",
        ring: "inset-ring-honey-600/20",
        dark_bg: "dark:bg-honey-800/20",
        dark_ring: "dark:inset-ring-honey-300/30",
        title: "text-honey-800 dark:text-honey-300",
        subtitle: "text-honey-700 dark:text-honey-400"
      }
    end
  end

  def calories_per_serving(meal)
    return 0 if meal.recipe.servings.zero?
    (meal.recipe.total_calories.to_f / meal.recipe.servings).to_i
  end
end