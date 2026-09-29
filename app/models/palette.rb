# The six named colors people pick for calendars and household members.
# Tailwind classes are spelled out in full (not interpolated) so the CSS
# build can see them.
module Palette
  NAMES = %w[olive seafoam honey mist mauve dusty-rose].freeze

  # For a person: a dot (pickers, member list), a pill (their name on to-do
  # cards), and a card tint (chore cards on the Chore Chart, which are
  # colored by assignee instead of carrying a name pill — see
  # weekly_chores/_assignee_key).
  PERSON_CLASSES = {
    "olive"      => { dot: "bg-olive-500",      pill: "bg-olive-100 text-olive-800 dark:bg-olive-800/40 dark:text-olive-200",
                    card: "bg-olive-100 border-olive-300 dark:bg-olive-800/40 dark:border-olive-600" },
    "seafoam"    => { dot: "bg-seafoam-500",    pill: "bg-seafoam-100 text-seafoam-800 dark:bg-seafoam-900/40 dark:text-seafoam-300",
                    card: "bg-seafoam-100 border-seafoam-300 dark:bg-seafoam-900/40 dark:border-seafoam-700" },
    "honey"      => { dot: "bg-honey-500",      pill: "bg-honey-100 text-honey-800 dark:bg-honey-900/40 dark:text-honey-300",
                    card: "bg-honey-100 border-honey-300 dark:bg-honey-900/40 dark:border-honey-700" },
    "mist"       => { dot: "bg-mist-500",       pill: "bg-mist-100 text-mist-800 dark:bg-mist-800/40 dark:text-mist-200",
                    card: "bg-mist-100 border-mist-300 dark:bg-mist-800/40 dark:border-mist-600" },
    "mauve"      => { dot: "bg-mauve-500",      pill: "bg-mauve-100 text-mauve-800 dark:bg-mauve-800/40 dark:text-mauve-200",
                    card: "bg-mauve-100 border-mauve-300 dark:bg-mauve-800/40 dark:border-mauve-600" },
    "dusty-rose" => { dot: "bg-dusty-rose-500", pill: "bg-dusty-rose-100 text-dusty-rose-800 dark:bg-dusty-rose-900/40 dark:text-dusty-rose-300",
                    card: "bg-dusty-rose-100 border-dusty-rose-300 dark:bg-dusty-rose-900/40 dark:border-dusty-rose-700" }
  }.freeze

  # For printing (WeekPlanPdf), as RGB hex converted from the app's oklch
  # palette: the 100 tint behind cards, the 500 shade for legend dots, 800
  # for text.
  PRINT = {
    "olive"      => { bg: "f4f4f0", dot: "7c7c67", text: "2b2b22" },
    "seafoam"    => { bg: "e1f3ef", dot: "76a39b", text: "354d4b" },
    "honey"      => { bg: "f2efe0", dot: "cbb673", text: "63532c" },
    "mist"       => { bg: "f1f3f3", dot: "67787c", text: "22292b" },
    "mauve"      => { bg: "f3f1f3", dot: "79697b", text: "2a212c" },
    "dusty-rose" => { bg: "fce9ea", dot: "a7787c", text: "4d3236" }
  }.freeze

  def self.person_classes(name) = PERSON_CLASSES.fetch(name.to_s, PERSON_CLASSES["olive"])
  def self.print_colors(name)   = PRINT.fetch(name.to_s, PRINT["olive"])
end
