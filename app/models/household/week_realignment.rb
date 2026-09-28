# Re-keys a household's week-based records after its week start day changes,
# so this week's and future weeks' chore charts, weekly plans and grocery
# lists show up under the new week boundaries. Past weeks are left alone.
#
# Records tied to a specific day (scheduled chores) move into whichever new
# week contains that day. Records that describe a whole week (plans, grocery
# lists, unscheduled chores) move to the new week sharing the most days with
# their old week (4 or more — there's always exactly one).
class Household::WeekRealignment
  def initialize(household, from:, to:)
    @household = household
    @from      = from
    @to        = to
    @to_symbol = Date::DAYNAMES.fetch(to).downcase.to_sym
  end

  def call
    return if @from == @to

    # Any old week that overlaps the new current week (or later) counts as
    # current — it may hold days that now belong to this week.
    cutoff = Date.current.beginning_of_week(@to_symbol) - 6

    realign_weekly_plans(cutoff)
    realign_weekly_chores(cutoff)
    realign_grocery_lists(cutoff)
  end

  private

  attr_reader :household

  def containing_week_start(date)
    date.beginning_of_week(@to_symbol)
  end

  def overlapping_week_start(old_week_start)
    candidate = containing_week_start(old_week_start)
    (old_week_start - candidate).to_i <= 3 ? candidate : candidate + 7
  end

  def realign_weekly_plans(cutoff)
    moving = household.weekly_plans.where(week_start: cutoff..).reject { |p| p.week_start.wday == @to }
    return if moving.empty?

    targets = moving.to_h { |plan| [ plan, overlapping_week_start(plan.week_start) ] }

    # Plans already sitting on a target week (left over from an earlier start
    # day) give way to the plan being moved there.
    household.weekly_plans.where(week_start: targets.values).where.not(id: moving.map(&:id)).destroy_all

    targets.group_by { |_plan, target| target }.each do |target, pairs|
      keep, *extra = pairs.map(&:first).sort_by(&:updated_at).reverse
      extra.each(&:destroy!)
      keep.update_columns(week_start: target)
    end
  end

  def realign_weekly_chores(cutoff)
    moving = household.weekly_chores.where(week_start: cutoff..).filter_map do |wc|
      target = wc.scheduled_date ? containing_week_start(wc.scheduled_date) : overlapping_week_start(wc.week_start)
      [ wc, target ] unless target == wc.week_start
    end
    return if moving.empty?

    # Chores staying put that already occupy a target week for the same chore.
    staying = household.weekly_chores
                       .where(week_start: moving.map(&:last).uniq)
                       .where.not(id: moving.map { |wc, _| wc.id })
                       .map { |wc| [ wc, wc.week_start ] }

    # A chore can only appear once per week. When two instances land in the
    # same new week, keep the completed one (or else the earliest scheduled).
    # delete, not destroy — destroy would clear the chore's remembered weekday.
    (moving + staying).group_by { |wc, target| [ wc.chore_id, target ] }.each_value do |pairs|
      keep, *extra = pairs.sort_by { |wc, _| [ wc.completed? ? 0 : 1, wc.scheduled_date&.jd || Float::INFINITY, wc.id ] }
      extra.each { |wc, _| wc.delete }

      wc, target = keep
      # update_columns skips the reschedule callbacks — the chore's day isn't
      # changing, only which week it's filed under.
      wc.update_columns(week_start: target) unless wc.week_start == target
    end
  end

  def realign_grocery_lists(cutoff)
    household.grocery_lists.where(week_of: cutoff..).distinct.pluck(:week_of).each do |week_of|
      target = overlapping_week_start(week_of)
      household.grocery_lists.where(week_of: week_of).update_all(week_of: target) unless target == week_of
    end
  end
end
