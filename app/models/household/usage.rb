# How much a household uses each part of the app, for the admin household
# page: per feature, how many in all, how many in the last 30 days, and when
# it was last used.
#
# Counts are of things people did, not things the app made for them — new
# households start with default restock items and tags, recurring rules
# fill in meals, and chore templates add whole categories at once — so
# restock is counted by items checked off, meals by hand-planned ones, and
# chores by ones ticked off.
class Household::Usage
  RECENT = 30.days

  Row = Data.define(:feature, :total, :recent, :last_at)

  def initialize(household)
    @household = household
    @user_ids  = household.users.select(:id)
    @since     = RECENT.ago
  end

  def rows
    [
      row("Recipes",                Recipe.where(user_id: @user_ids)),
      row("Recipe imports",         RecipeImportJob.where(user_id: @user_ids)),
      row("Collections",            Collection.where(user_id: @user_ids)),
      row("Favorites",              UserFavorite.where(user_id: @user_ids)),
      row("Meals planned by hand",  @household.meals.where(recurring_meal_id: nil)),
      row("Recurring meals",        @household.recurring_meals),
      row("Weekly plans finished",  @household.weekly_plans.where.not(planning_completed_at: nil), at: :planning_completed_at),
      row("Grocery list items",     @household.grocery_lists),
      row("Receipt scans",          @household.receipt_scans),
      row("To-dos added",           @household.todos),
      row("Chores ticked off",      @household.weekly_chores.where(completed: true), at: :completed_at),
      restock_row,
      row("Calendars connected",    @household.calendar_sources, at: :created_at, last: :last_synced_at)
    ]
  end

  private

  # `at` is what "last 30 days" counts by; `last` is what "last used" shows
  # (the same unless said otherwise).
  def row(feature, scope, at: :created_at, last: at)
    Row.new(feature:, total: scope.count, recent: scope.where(at => @since..).count, last_at: scope.maximum(last))
  end

  # Items checked off as stocked or needing restock — they come seeded, so
  # the total is the list's size and the rest is about checking it.
  def restock_row
    items = @household.restock_items
    checked = items.where(last_date_checked_stocked: @since..).or(items.where(last_date_checked_restocked: @since..))

    Row.new(feature: "Restock items (checked lately)", total: items.count, recent: checked.count,
            last_at: [ items.maximum(:last_date_checked_stocked), items.maximum(:last_date_checked_restocked) ].compact.max)
  end
end
