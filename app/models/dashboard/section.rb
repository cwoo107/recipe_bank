module Dashboard
  # Base interface for a single dashboard card / wizard step. Not persisted —
  # wraps live data from the real feature tables plus this week's status row.
  # Subclasses set KEY/LABEL/ICON and implement the methods below.
  class Section
    include Rails.application.routes.url_helpers

    attr_reader :household, :week_start, :weekly_plan

    def initialize(household:, week_start:, weekly_plan:)
      @household = household
      @week_start = week_start
      @weekly_plan = weekly_plan
    end

    def key   = self.class::KEY
    def label = self.class::LABEL
    def icon_name = self.class::ICON

    def weekly_plan_section
      @weekly_plan_section ||= weekly_plan.section(key)
    end

    def status = weekly_plan_section.status

    def week_range
      week_start...(week_start + 7)
    end

    def step_path
      plan_week_step_path(section: key)
    end

    # Override in subclasses:
    def empty?         = raise NotImplementedError
    def summary_line   = raise NotImplementedError
    def detail_line    = nil
    def empty_headline = raise NotImplementedError
    def empty_body     = raise NotImplementedError
    def cta_label      = raise NotImplementedError

    def cta_path
      step_path
    end
  end
end
