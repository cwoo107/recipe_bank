module MealsHelper
  # Each breakfast/lunch/dinner slot of a week, keyed "YYYY-MM-DD|breakfast",
  # with who has their own assigned meal there and the shared (unassigned)
  # meals planned there. The meal form uses it to default a shared meal's
  # servings (family minus those people) and, before saving, to ask whether
  # newly assigned people should come out of the shared meals' servings.
  # `except` leaves out the meal being edited.
  def meal_slot_data(household, week_start, except: nil)
    meals = household.meals.where(date: week_start...(week_start + 7)).where.not(id: except&.id)
                     .includes(:recipe, :meal_assignments)
                     .select(&:calendar_meal?)

    meals.group_by { |meal| "#{meal.date.iso8601}|#{meal.meal_name.downcase}" }.transform_values do |slot_meals|
      assigned, shared = slot_meals.partition(&:assigned?)
      {
        assigned: assigned.flat_map(&:eater_ids_assigned).uniq,
        shared:   shared.map { |meal| { id: meal.id, title: meal.recipe.title, servings: meal.servings } }
      }
    end
  end

  def meal_color_classes(meal)
    case meal.meal_name.downcase
    when "breakfast"
      {
        bg: "bg-seafoam-300",
        hover: "hover:bg-seafoam-400 dark:hover:bg-seafoam-600",
        ring: "inset-ring-seafoam-600/20",
        dark_bg: "dark:bg-seafoam-800/20",
        dark_ring: "dark:inset-ring-seafoam-300/30",
        title: "text-seafoam-800 dark:text-seafoam-300",
        subtitle: "text-seafoam-700 dark:text-seafoam-400"
      }
    when "lunch"
      {
        bg: "bg-honey-300",
        hover: "hover:bg-honey-400  dark:hover:bg-honey-600",
        ring: "inset-ring-honey-600/20",
        dark_bg: "dark:bg-honey-800/20",
        dark_ring: "dark:inset-ring-honey-300/30",
        title: "text-honey-800 dark:text-honey-300",
        subtitle: "text-honey-700 dark:text-honey-400"
      }
    when "dinner"
      {
        bg: "bg-mist-300",
        hover: "hover:bg-mist-400 dark:hover:bg-mist-600",
        ring: "inset-ring-mist-600/20",
        dark_bg: "dark:bg-mist-800/20",
        dark_ring: "dark:inset-ring-mist-300/30",
        title: "text-mist-800 dark:text-mist-300",
        subtitle: "text-mist-700 dark:text-mist-400"
      }
    when "snack"
      {
        bg: "bg-mauve-300",
        hover: "hover:bg-mauve-400 dark:hover:bg-mauve-600",
        ring: "inset-ring-mauve-600/20",
        dark_bg: "dark:bg-mauve-800/20",
        dark_ring: "dark:inset-ring-mauve-300/30",
        title: "text-mauve-800 dark:text-mauve-300",
        subtitle: "text-mauve-700 dark:text-mauve-400"
      }
    when "dessert"
      {
        bg: "bg-dusty-rose-300",
        hover: "hover:bg-dusty-rose-400 dark:hover:bg-dusty-rose-600",
        ring: "inset-ring-dusty-rose-600/20",
        dark_bg: "dark:bg-dusty-rose-800/20",
        dark_ring: "dark:inset-ring-dusty-rose-300/30",
        title: "text-dusty-rose-800 dark:text-dusty-rose-300",
        subtitle: "text-dusty-rose-700 dark:text-dusty-rose-400"
      }
    else
      {
        bg: "bg-honey-300",
        hover: "hover:bg-honey-400 dark:hover:bg-honey-600",
        ring: "inset-ring-honey-600/20",
        dark_bg: "dark:bg-honey-800/20",
        dark_ring: "dark:inset-ring-honey-300/30",
        title: "text-honey-800 dark:text-honey-300",
        subtitle: "text-honey-700 dark:text-honey-400"
      }
    end
  end
end