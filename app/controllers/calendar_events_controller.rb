class CalendarEventsController < ApplicationController
  before_action :authenticate_user!
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: :show
  before_action :set_event, only: [:show, :edit, :update, :destroy]
  # Events that came from a feed are read-only here — the next sync would
  # overwrite any change (CalendarSyncJob). Change them in the calendar app.
  before_action :require_local_event!, only: [:edit, :update, :destroy]

  def show

  end

  def new
    @event = current_household.calendar_events.build(
      starts_at: parse_datetime(params[:starts_at]) || Time.zone.now.beginning_of_hour + 1.hour,
      ends_at:   parse_datetime(params[:ends_at])   || Time.zone.now.beginning_of_hour + 2.hours,
      all_day:   params[:all_day] == "true",
      calendar_source_id: params[:calendar_source_id] || current_household.calendar_sources.first&.id
    )
    @sources = current_household.calendar_sources.ordered
    @return_to = calendar_return_path
  end

  def create
    @event = current_household.calendar_events.build(event_params)
    @sources = current_household.calendar_sources.ordered
    if @event.save
      redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event created.", status: :see_other
    else
      @return_to = calendar_return_path
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sources = current_household.calendar_sources.ordered
    @return_to = calendar_return_path
  end

  def update
    @sources = current_household.calendar_sources.ordered
    if @event.update(event_params)
      redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event updated.", status: :see_other
    else
      @return_to = calendar_return_path
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    date = @event.starts_at.to_date
    @event.destroy
    redirect_to day_calendars_path(date: date), notice: "Event removed.", status: :see_other
  end

  private

  def set_event
    @event = current_household.calendar_events.find(params[:id])
  end

  # Where Cancel goes: the calendar page you came from (month, week or day),
  # carried through failed saves in a hidden field — else the month the event
  # is in. Only local /calendar pages, so this can't redirect off-site.
  def calendar_return_path
    candidate = params[:return_to].presence || request.referer
    path = begin
      uri = URI.parse(candidate.to_s)
      [ uri.path, uri.query ].compact.join("?") if uri.host.nil? || uri.host == request.host
    rescue URI::InvalidURIError
      nil
    end
    return path if path&.match?(%r{\A/calendar(/|\?|\z)})

    date = (@event&.starts_at || Time.current).to_date
    month_calendars_path(year: date.year, month: date.month)
  end

  def require_local_event!
    return unless @event.synced?

    redirect_to day_calendars_path(date: @event.starts_at.to_date),
                alert: "“#{@event.title}” comes from #{@event.source_name} — change it there.", status: :see_other
  end

  # The form sends each time as a date and a time of day (starts_on +
  # starts_time); they're put back together as starts_at / ends_at in the
  # household's zone. starts_at / ends_at sent whole still work.
  def event_params
    params.require(:calendar_event).permit(
      :title, :description, :location, :starts_at, :ends_at,
      :starts_on, :starts_time, :ends_on, :ends_time,
      :all_day, :calendar_source_id, :url, :status
    ).tap do |p|
      %w[starts ends].each do |key|
        date, time = p.delete("#{key}_on"), p.delete("#{key}_time")
        p["#{key}_at"] = combine_date_and_time(date, time) unless date.nil?
      end
      p[:user_id] = current_user.id
    end
  end

  # A blank or unreadable date gives nil, so the model's presence check
  # reports it.
  def combine_date_and_time(date, time)
    day = Date.iso8601(date.to_s)
    hour, minute = time.to_s.split(":").map(&:to_i)
    Time.zone.local(day.year, day.month, day.day, hour || 0, minute || 0)
  rescue ArgumentError, Date::Error
    nil
  end

  def parse_datetime(val)
    Time.zone.parse(val) rescue nil
  end
end