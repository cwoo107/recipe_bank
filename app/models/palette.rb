# The six named colors people pick for calendars and household members.
# Tailwind classes are spelled out in full (not interpolated) so the CSS
# build can see them.
module Palette
  NAMES = %w[olive seafoam honey mist mauve dusty-rose].freeze

  # For a person: a dot (pickers, member list), a pill (their name on to-do
  # cards), and a card tint (chore cards on the Chore Chart, which are
  # colored by assignee instead of carrying a name pill — see
  # weekly_chores/_assignee_key). The card uses the 300 shade, like the meal
  # planner's cards (MealsHelper#meal_color_classes), so people are easy to
  # tell apart at a glance.
  PERSON_CLASSES = {
    "olive"      => { dot: "bg-olive-500",      pill: "bg-olive-100 text-olive-800 dark:bg-olive-800/40 dark:text-olive-200",
                    card: "bg-olive-300 border-olive-400 dark:bg-olive-700/60 dark:border-olive-500" },
    "seafoam"    => { dot: "bg-seafoam-500",    pill: "bg-seafoam-100 text-seafoam-800 dark:bg-seafoam-900/40 dark:text-seafoam-300",
                    card: "bg-seafoam-300 border-seafoam-400 dark:bg-seafoam-800/60 dark:border-seafoam-600" },
    "honey"      => { dot: "bg-honey-500",      pill: "bg-honey-100 text-honey-800 dark:bg-honey-900/40 dark:text-honey-300",
                    card: "bg-honey-300 border-honey-400 dark:bg-honey-800/60 dark:border-honey-600" },
    "mist"       => { dot: "bg-mist-500",       pill: "bg-mist-100 text-mist-800 dark:bg-mist-800/40 dark:text-mist-200",
                    card: "bg-mist-300 border-mist-400 dark:bg-mist-700/60 dark:border-mist-500" },
    "mauve"      => { dot: "bg-mauve-500",      pill: "bg-mauve-100 text-mauve-800 dark:bg-mauve-800/40 dark:text-mauve-200",
                    card: "bg-mauve-300 border-mauve-400 dark:bg-mauve-700/60 dark:border-mauve-500" },
    "dusty-rose" => { dot: "bg-dusty-rose-500", pill: "bg-dusty-rose-100 text-dusty-rose-800 dark:bg-dusty-rose-900/40 dark:text-dusty-rose-300",
                    card: "bg-dusty-rose-300 border-dusty-rose-400 dark:bg-dusty-rose-800/60 dark:border-dusty-rose-600" }
  }.freeze

  # For printing (WeekPlanPdf), as RGB hex converted from the app's oklch
  # palette: the 100 tint behind calendar event cards (bg), the 500 shade for
  # legend dots, 800 for text.
  #
  # A person's chore and to-do cards (card) sit halfway between the 100 and
  # 300 shades (averaged in oklch) — deeper than bg so people are easier to
  # tell apart on paper, a little lighter than the on-screen chore cards'
  # 300 so the page doesn't print heavy.
  PRINT = {
    "olive"      => { bg: "f4f4f0", card: "e6e6e0", dot: "7c7c67", text: "2b2b22" },
    "seafoam"    => { bg: "e1f3ef", card: "c5e0da", dot: "76a39b", text: "354d4b" },
    "honey"      => { bg: "f2efe0", card: "ebe3c6", dot: "cbb673", text: "63532c" },
    "mist"       => { bg: "f1f3f3", card: "e0e5e5", dot: "67787c", text: "22292b" },
    "mauve"      => { bg: "f3f1f3", card: "e5e0e5", dot: "79697b", text: "2a212c" },
    "dusty-rose" => { bg: "fce9ea", card: "e9cecf", dot: "a7787c", text: "4d3236" }
  }.freeze

  def self.person_classes(name) = PERSON_CLASSES.fetch(name.to_s, PERSON_CLASSES["olive"])
  def self.print_colors(name)   = PRINT.fetch(name.to_s, PRINT["olive"])
end
