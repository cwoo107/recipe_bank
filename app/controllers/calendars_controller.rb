class CalendarsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_view_params

  def index
    today = Time.zone.today
    redirect_to month_calendars_path(year: today.year, month: today.month)
  end

  def month
    if params[:year].present? && params[:month].present?
      @date = Date.new(params[:year].to_i, params[:month].to_i, 1) rescue Time.zone.today.beginning_of_month
    else
      @date = Time.zone.today.beginning_of_month
    end

    @range_start = @date.beginning_of_month.beginning_of_week(:sunday)
    @range_end   = @date.end_of_month.end_of_week(:sunday)

    load_events(@range_start, @range_end + 1.day)
    @events_by_date = group_events_by_date(@events, @range_start, @range_end)
  end

  def week
    @date      = params[:date].present? ? Date.parse(params[:date]) : Time.zone.today
    @date      = @date.beginning_of_week(:sunday)
    @range_end = @date.end_of_week(:sunday)

    load_events(@date, @range_end + 1.day)
    @events_by_day  = group_events_by_day(@events, @date, @range_end)
    @all_day_events = @events.select(&:all_day?)
    @timed_events   = @events.reject(&:all_day?)
  end

  def day
    @date = params[:date].present? ? Date.parse(params[:date]) : Time.zone.today

    load_events(@date.beginning_of_day, @date.end_of_day)
    @all_day_events = @events.select(&:all_day?)
    @timed_events   = @events.reject(&:all_day?).sort_by(&:starts_at)
    @hours          = (0..23).to_a
  end

  private

  def set_view_params
    @sources    = current_household.calendar_sources.ordered
    @today      = Time.zone.today   # available in all views for the switcher
  end

  def load_events(from, to)
    @events = current_household.calendar_events
                          .visible
                          .in_range(from, to)
                          .includes(:calendar_source)
                          .chronological
  end

  def group_events_by_date(events, range_start, range_end)
    result = {}
    (range_start..range_end).each { |d| result[d] = [] }
    events.each do |event|
      event_start = [event.starts_at.to_date, range_start].max
      event_end   = [event.ends_at.to_date,   range_end  ].min
      (event_start..event_end).each { |d| result[d] << event if result.key?(d) }
    end
    result
  end

  def group_events_by_day(events, range_start, range_end)
    result = {}
    (range_start..range_end).each { |d| result[d] = [] }
    events.each do |event|
      day = event.starts_at.to_date
      result[day] << event if result.key?(day)
    end
    result
  end
end