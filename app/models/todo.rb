class Todo < ApplicationRecord
  belongs_to :user
  belongs_to :household

  acts_as_list scope: [ :household_id, :status ]

  STATUSES   = %w[todo in_progress done].freeze
  PRIORITIES = { low: 1, medium: 2, high: 3, urgent: 4 }.freeze

  # Canvas (Chart.js) colours, pulled from the Design Guide palette.
  PRIORITY_CHART_COLORS = {
    "low"    => "#95a97d", # seafoam / sage
    "medium" => "#e7c878", # honey
    "high"   => "#a98fb0", # mauve
    "urgent" => "#d39a86"  # dusty-rose
  }.freeze
  DONE_CHART_COLOR = "#c2c8ba".freeze # muted sage-grey ("greyed out")

  enum :priority, PRIORITIES, prefix: :priority

  # Virtual fields used by the "Add a task" form (hours + minutes -> minutes).
  attribute :estimated_hours,   :integer
  attribute :estimated_minutes, :integer

  after_initialize :set_default_priority, if: :new_record?
  before_validation :compose_estimated_time,
                    if: -> { estimated_hours.present? || estimated_minutes.present? }

  validates :title,    presence: true
  validates :priority, presence: true
  validates :status,   inclusion: { in: STATUSES }

  scope :ordered,   -> { order(:position) }
  scope :by_status, ->(s) { where(status: s).ordered }

  # Todos whose end_date lands inside the current (Mon–Sun) week. Used to keep
  # the "done" column from accumulating stale, already-completed items — the
  # week boundaries here match the Gantt's beginning_of_week anchor.
  scope :ended_this_week, lambda {
    week_start = Date.current.beginning_of_week.beginning_of_day
    week_end   = Date.current.end_of_week.end_of_day
    where(end_date: week_start..week_end)
  }

  # ── Human-readable helpers ────────────────────────────────────────────

  PRIORITY_LABELS = {
    "low" => "Low", "medium" => "Medium", "high" => "High", "urgent" => "Urgent"
  }.freeze

  STATUS_LABELS = {
    "todo" => "To Do", "in_progress" => "In Progress", "done" => "Done"
  }.freeze

  def priority_label = PRIORITY_LABELS[priority]
  def status_label   = STATUS_LABELS[status]

  def self.humanize_minutes(minutes)
    minutes = minutes.to_i
    return "—" if minutes <= 0
    hours, mins = minutes.divmod(60)
    parts = []
    parts << "#{hours}h" if hours.positive?
    parts << "#{mins}m"  if mins.positive? || parts.empty?
    parts.join(" ")
  end

  def estimated_hm = self.class.humanize_minutes(estimated_time_to_complete)
  def actual_hm    = self.class.humanize_minutes(actual_time_to_complete)

  # ── Column moves (kept compatible with the existing kanban) ───────────

  def move_to_column!(new_status, new_position = nil)
    return if new_status == status && (new_position.nil? || new_position == position)

    old_status  = status
    self.status = new_status
    remove_from_list if old_status != new_status

    if new_position
      insert_at(new_position.to_i)
    else
      move_to_bottom
    end
  end

  # Apply the field side-effects of a status change. Call AFTER the status
  # itself has been set/saved. `previous_status` lets us tell
  # "in_progress -> done" apart from "todo -> done".
  #
  # Returns the cursor date that `reschedule_in_progress!` should pack the
  # rest of the household's queue from, or `false` if no one else's schedule
  # needs to move at all. Callers should feed this straight into
  # `reschedule_in_progress!(household, from: ...)` (skipping the call
  # entirely when it's `false`).
  def apply_status_side_effects!(previous_status)
    reschedule_from = Date.current

    case status
    when "done"
      self.completed = true

      if previous_status == "in_progress" && start_date.present?
        if start_date.to_date > Date.current
          # Completed ahead of its scheduled slot — it jumped the queue, so
          # it now occupies today instead of its original future start date,
          # and whatever was queued behind it shifts up to fill in after it.
          self.start_date = Date.current.beginning_of_day
          self.end_date   = Date.current.end_of_day
          reschedule_from = Date.current + 1
        else
          # Already at (or before) the front of the queue — completing it
          # right on schedule doesn't free up or disturb anyone else's slot.
          reschedule_from = false
        end

        # Worked across N calendar days -> N * household.minutes_per_day.
        self.actual_time_to_complete = inclusive_minutes_between(start_date, end_date)
      else
        # Straight from "todo" (or no recorded start): trust the estimate and
        # reverse-derive a start date from the completion timestamp.
        self.actual_time_to_complete = estimated_time_to_complete
        self.start_date              = reverse_start_from(end_date, estimated_time_to_complete)
      end

    when "in_progress"
      self.completed               = false
      self.actual_time_to_complete = nil
      # start_date / end_date are (re)assigned by reschedule_in_progress!

    when "todo"
      self.completed               = false
      self.actual_time_to_complete = nil
      self.start_date              = nil
      self.end_date                = nil
    end

    save!
    reschedule_from
  end

  # ── The scheduler ─────────────────────────────────────────────────────
  #
  # Lays out every "in_progress" todo for a user along a timeline where each
  # calendar day = household.minutes_per_day of capacity. Higher priority is
  # scheduled first; ties fall back to the user's kanban order (position),
  # then id.
  #
  # Todos that have already started in the past (start_date < today) are
  # treated as "in flight" and keep their original start_date, so completing
  # a long-running task still reports the right actual time. Everything else
  # is (re)packed by priority starting from `from` (today by default) — which
  # is what pushes a low-priority task later when an urgent one is dropped
  # in, or later still when a same-day slot was already spent on a todo that
  # jumped the queue (see `apply_status_side_effects!`).
  def self.reschedule_in_progress!(household, from: Date.current)
    today          = Date.current
    minutes_per_day = household.minutes_per_day

    transaction do
      todos = household.todos.where(status: "in_progress").to_a
      in_flight, queued = todos.partition { |t| t.start_date.present? && t.start_date.to_date < today }

      # In-flight: freeze the start, refresh the end from the estimate.
      in_flight.each do |t|
        days = days_for_minutes(t.estimated_time_to_complete, minutes_per_day)
        end_day = t.start_date.to_date + (days - 1)
        t.update_columns(end_date: end_day.end_of_day, completed: false, updated_at: Time.current)
      end

      # Queued: pack by priority starting from the given cursor.
      ordered = queued.sort_by { |t| [ -priority_rank(t), t.position.to_i, t.id ] }
      cursor  = from
      ordered.each do |t|
        days      = days_for_minutes(t.estimated_time_to_complete, minutes_per_day)
        start_day = cursor
        end_day   = cursor + (days - 1)
        t.update_columns(
          start_date: start_day.beginning_of_day,
          end_date:   end_day.end_of_day,
          completed:  false,
          updated_at: Time.current
        )
        cursor = end_day + 1
      end
    end
  end

  def self.priority_rank(todo)
    PRIORITIES.fetch(todo.priority&.to_sym, 0)
  end

  def self.days_for_minutes(minutes, minutes_per_day)
    [ (minutes.to_f / minutes_per_day).ceil, 1 ].max
  end

  # ── Gantt data (consumed by gantt_controller.js) ──────────────────────
  #
  # Always spans the current week (Mon..Sun). Excludes "todo". Offsets are in
  # day-units measured from the start of the week and clamped to [0, 7], so
  # the controller never needs a date adapter.
  def self.gantt_data(household)
    week_start = Date.current.beginning_of_week # Monday
    days = (0..6).map do |i|
      d = week_start + i
      { label: d.strftime("%a"), date: d.strftime("%-d"), month: d.strftime("%b") }
    end

    today_offset = ((Time.current - week_start.to_time) / 1.day.to_i).round(3).clamp(0, 7)

    rows = household.todos
               .where(status: %w[in_progress done])
               .where.not(start_date: nil).where.not(end_date: nil)
               .order(:start_date, :end_date, :id)
               .filter_map { |t| t.gantt_row(week_start) }

    {
      week_start:   week_start.iso8601,
      week_label:   "#{week_start.strftime('%b %-d')} – #{(week_start + 6).strftime('%b %-d')}",
      days:         days,
      today_offset: today_offset,
      rows:         rows
    }
  end

  def gantt_row(week_start)
    return nil if start_date.blank? || end_date.blank?

    start_offset = (start_date.to_date - week_start).to_i
    end_offset   = (end_date.to_date - week_start).to_i + 1 # +1 so a single day has width 1

    s = start_offset.clamp(0, 7)
    e = end_offset.clamp(0, 7)
    return nil if e <= s # nothing visible inside this week

    {
      id:          id,
      title:       title,
      start:       s,
      end:         e,
      color:       gantt_color,
      status:      status,
      range_label: "#{start_date.strftime('%a %-d')} → #{end_date.strftime('%a %-d')}",
      meta: if status == "done"
              "Done · #{actual_hm}"
            else
              "#{priority_label} · #{estimated_hm}"
            end
    }
  end

  def gantt_color
    status == "done" ? DONE_CHART_COLOR : PRIORITY_CHART_COLORS.fetch(priority, "#95a97d")
  end

  # ── Live chart updates over Turbo Streams ─────────────────────────────
  def self.broadcast_gantt(household)
    Turbo::StreamsChannel.broadcast_replace_to(
      household, "todos_gantt",
      target:  "gantt_chart",
      partial: "todos/gantt",
      locals:  { household: household }
    )
  end

  private

  def set_default_priority
    self.priority ||= :medium
  end

  def compose_estimated_time
    self.estimated_time_to_complete = estimated_hours.to_i * 60 + estimated_minutes.to_i
  end

  def inclusive_minutes_between(start_at, end_at)
    return 0 if start_at.blank? || end_at.blank?
    days = (end_at.to_date - start_at.to_date).to_i + 1
    days = 1 if days < 1
    days * household.minutes_per_day
  end

  def reverse_start_from(end_at, minutes)
    days = self.class.days_for_minutes(minutes, household.minutes_per_day)
    (end_at.to_date - (days - 1)).beginning_of_day
  end
end