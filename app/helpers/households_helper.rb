module HouseholdsHelper
  # What each "Plan your week" step covers, under its checkbox in the
  # household settings (keyed by Dashboard section KEY).
  PLANNER_STEP_DESCRIPTIONS = {
    "meals"     => "Choose breakfast, lunch and dinner for each day.",
    "restock"   => "Check what's running low around the house.",
    "groceries" => "Build the week's shopping list.",
    "chores"    => "Put the week's chores on the chart.",
    "todos"     => "Schedule the to-dos you're working on.",
    "calendar"  => "Look over the week's events."
  }.freeze

  def planner_step_description(key) = PLANNER_STEP_DESCRIPTIONS[key.to_s]

  # Shared classes for the settings form's controls, so every field matches.
  SETTINGS_INPUT_CLASSES = "block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 " \
                           "placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-[#5f734c] sm:text-sm/6 " \
                           "dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-[#7a8f62]".freeze

  SETTINGS_SELECT_CLASSES = "col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 " \
                            "outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-[#5f734c] sm:text-sm/6 " \
                            "dark:bg-white/5 dark:text-white dark:outline-white/10 dark:*:bg-gray-800 dark:focus:outline-[#7a8f62]".freeze

  def settings_input_classes  = SETTINGS_INPUT_CLASSES
  def settings_select_classes = SETTINGS_SELECT_CLASSES
end
