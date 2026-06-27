class CalendarEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event, only: [:show, :edit, :update, :destroy]

  def show

  end

  def new
    @event = current_user.calendar_events.build(
      starts_at: parse_datetime(params[:starts_at]) || Time.zone.now.beginning_of_hour + 1.hour,
      ends_at:   parse_datetime(params[:ends_at])   || Time.zone.now.beginning_of_hour + 2.hours,
      all_day:   params[:all_day] == "true",
      calendar_source_id: params[:calendar_source_id] || current_user.calendar_sources.first&.id
    )
    @sources = current_user.calendar_sources.ordered
  end

  def create
    @event = current_user.calendar_events.build(event_params)
    @sources = current_user.calendar_sources.ordered
    if @event.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event created." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sources = current_user.calendar_sources.ordered
  end

  def update
    @sources = current_user.calendar_sources.ordered
    if @event.update(event_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to day_calendars_path(date: @event.starts_at.to_date), notice: "Event updated." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    date = @event.starts_at.to_date
    @event.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to day_calendars_path(date: date), notice: "Event removed." }
    end
  end

  private

  def set_event
    @event = current_user.calendar_events.find(params[:id])
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