class Todo < ApplicationRecord
  belongs_to :user
  # Optional — who's doing it. See HouseholdMember#todos.
  belongs_to :assignee, class_name: "HouseholdMember", optional: true
  belongs_to :household

  has_many :todo_taggings, dependent: :destroy
  has_many :tags, -> { order(:name) }, through: :todo_taggings, source: :todo_tag

  acts_as_list scope: [ :household_id, :status ]

  # "in_progress" is the "To-Do This Week" column — the stored name predates
  # the board's weekly columns.
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
  after_save :apply_tag_names, if: -> { @tag_names }
  before_validation :compose_estimated_time,
                    if: -> { estimated_hours.present? || estimated_minutes.present? }

  validates :title,    presence: true
  validates :priority, presence: true
  validates :status,   inclusion: { in: STATUSES }

  scope :ordered,   -> { order(:position) }
  scope :by_status, ->(s) { where(status: s).ordered }

  # Todos whose end_date (when they were completed) lands inside the given
  # 7-day week. Keeps the "Completed" column from accumulating stale items.
  scope :ended_in_week, lambda { |week_start|
    where(end_date: week_start.beginning_of_day..(week_start + 6).end_of_day)
  }
  scope :ended_this_week, -> { ended_in_week(Date.current.beginning_of_week) }

  # ── Human-readable helpers ────────────────────────────────────────────

  PRIORITY_LABELS = {
    "low" => "Low", "medium" => "Medium", "high" => "High", "urgent" => "Urgent"
  }.freeze

  STATUS_LABELS = {
    "todo" => "To-Do", "in_progress" => "To-Do This Week", "done" => "Completed"
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

  # For sentences: "6 hours", "1 hour", "45 minutes", "1h 30m".
  def self.humanize_duration(minutes)
    minutes = minutes.to_i
    hours, mins = minutes.divmod(60)
    if mins.zero? && hours.positive? then "#{hours} #{'hour'.pluralize(hours)}"
    elsif hours.zero? then "#{mins} #{'minute'.pluralize(mins)}"
    else humanize_minutes(minutes)
    end
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
  # itself has been set. `previous_status` tells a fresh move into a column
  # apart from a save that left it where it was; `week` is the week a move
  # into "To-Do This Week" plans it for (the current one, unless "Plan your
  # week" is planning a later week).
  def apply_status_side_effects!(previous_status, week: Todo.current_week_start(household))
    case status
    when "done"
      self.completed = true
      self.end_date  = Time.current if previous_status != "done" || end_date.nil?
      self.actual_time_to_complete ||= estimated_time_to_complete
      # Finished now, so it took up this week's time — unless it was planned
      # for a week that hasn't started yet.
      self.planned_week = week if planned_week.nil? || planned_week < week

    when "in_progress"
      self.completed               = false
      self.actual_time_to_complete = nil
      self.start_date              = nil
      self.end_date                = nil
      self.planned_week = week if previous_status != "in_progress" || planned_week.nil?

    when "todo"
      self.completed               = false
      self.actual_time_to_complete = nil
      self.start_date              = nil
      self.end_date                = nil
      self.planned_week            = nil
    end

    save!
  end

  # ── The week's plan ───────────────────────────────────────────────────
  #
  # A household sets aside so much time a week for to-dos (see
  # Household#todo_minutes_budget). Moving a to-do into "To-Do This Week"
  # plans it for a week (planned_week); its estimate then counts against that
  # week's time, as does the time anything completed that week took.

  def self.current_week_start(household)
    Date.current.beginning_of_week(household.week_start_symbol)
  end

  # What's still to do in a week, in the This Week column's order (which is
  # also the Gantt's). The current week also carries anything left in the
  # column from earlier weeks — it's still there, waiting to be finished or
  # carried over (see .carried_over) — and anything older that was moved in
  # before weeks were tracked.
  def self.open_for_week(household, week_start)
    open = household.todos.where(status: "in_progress")
    open = if week_start == current_week_start(household)
             open.where(planned_week: ..week_start).or(open.where(planned_week: nil))
           else
             open.where(planned_week: week_start)
           end
    open.ordered
  end

  def self.done_for_week(household, week_start)
    household.todos.where(status: "done", planned_week: week_start).order(:end_date, :id)
  end

  # Still in "To-Do This Week" from a week before this one — for "Plan your
  # week" to finish off or carry over.
  def self.carried_over(household, week_start)
    open = household.todos.where(status: "in_progress")
    open.where(planned_week: ...week_start).or(open.where(planned_week: nil)).ordered
  end

  # What a to-do takes out of its week: the time it took once done, its
  # estimate until then.
  def minutes_for_week
    (completed? ? actual_time_to_complete || estimated_time_to_complete : estimated_time_to_complete).to_i
  end

  def gantt_color
    status == "done" ? DONE_CHART_COLOR : PRIORITY_CHART_COLORS.fetch(priority, "#95a97d")
  end

  # The form's tag picker sends the to-do's whole set of tags by name
  # ("Yard, Paperwork"); names the household doesn't have yet become new tags.
  def tag_name_list = @tag_names || tags.map(&:name)
  def tag_names     = tag_name_list.join(", ")

  def tag_names=(names)
    @tag_names = names.to_s.split(",").map(&:strip).compact_blank.uniq(&:downcase)
  end

  # ── Live chart updates over Turbo Streams ─────────────────────────────
  # The board's time meter and Gantt both follow the current week.
  def self.broadcast_gantt(household)
    budget = TodoBudget.new(household)
    Turbo::StreamsChannel.broadcast_replace_to(
      household, "todos_gantt",
      target: "todo_budget", partial: "todos/budget", locals: { budget: budget }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      household, "todos_gantt",
      target: "gantt_chart", partial: "todos/gantt", locals: { budget: budget }
    )
  end

  private

  def set_default_priority
    self.priority ||= :medium
  end

  def compose_estimated_time
    self.estimated_time_to_complete = estimated_hours.to_i * 60 + estimated_minutes.to_i
  end

  def apply_tag_names
    names = @tag_names
    @tag_names = nil
    self.tags = names.map do |name|
      household.todo_tags.where("LOWER(name) = ?", name.downcase).first || household.todo_tags.create!(name: name)
    end
  end
end