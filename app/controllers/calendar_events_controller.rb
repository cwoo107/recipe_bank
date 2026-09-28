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
  end

  def create
    @event = current_household.calendar_events.build(event_params)
    @sources = current_household.calendar_sources.ordered
    if @event.save
      redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sources = current_household.calendar_sources.ordered
  end

  def update
    @sources = current_household.calendar_sources.ordered
    if @event.update(event_params)
      redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event updated.", status: :see_other
    else
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

  def require_local_event!
    return unless @event.synced?

    redirect_to day_calendars_path(date: @event.starts_at.to_date),
                alert: "“#{@event.title}” comes from #{@event.source_name} — change it there.", status: :see_other
  end

  def event_params
    params.require(:calendar_event).permit(
      :title, :description, :location, :starts_at, :ends_at,
      :all_day, :calendar_source_id, :url, :status
    ).tap do |p|
      p[:user_id] = current_user.id
    end
  end

  def parse_datetime(val)
    Time.zone.parse(val) rescue nil
  end
end