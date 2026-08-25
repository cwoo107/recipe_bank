class CalendarSourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_source, only: [:edit, :update, :destroy, :toggle_visible, :sync]

  def index
    @sources = current_household.calendar_sources.ordered
  end

  def new
    @source = current_household.calendar_sources.build
  end

  def create
    @source = current_household.calendar_sources.build(source_params)
    @source.user = current_user
    if @source.save
      redirect_to calendars_path, notice: "#{@source.name} connected."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @source.update(source_params)
      respond_to do |format|
        format.html { redirect_to calendars_path, notice: "Calendar updated." }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy
    redirect_to calendars_path, notice: "Calendar removed."
  end

  def toggle_visible
    @source.update!(visible: !@source.visible)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: calendars_path }
    end
  end

  def reorder
    params[:order].each_with_index do |id, index|
      current_household.calendar_sources.where(id: id).update_all(position: index)
    end
    head :ok
  end

  def sync
    # Trigger a background job to sync this source
    CalendarSyncJob.perform_later(@source.id)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("source_#{@source.id}_status", partial: "calendar_sources/sync_status", locals: { source: @source, syncing: true }) }
      format.html { redirect_back fallback_location: calendars_path, notice: "Sync started." }
    end
  end

  private

  def set_source
    @source = current_household.calendar_sources.find(params[:id])
  end

  def source_params
    params.require(:calendar_source).permit(:name, :provider, :color, :ical_url, :visible)
  end
end