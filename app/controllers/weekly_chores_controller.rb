class WeeklyChoresController < ApplicationController
  before_action :set_weekly_chore, only: %i[update destroy move]

  def index
    @week_start = week_start_from_params
    Chore.auto_schedule_recurring!(current_household, week_start: @week_start)
    @weekly_chores = current_household.weekly_chores.for_week(@week_start).includes(:chore, :assignee)
    @due_chores = Chore.due_and_unscheduled(current_household, week_start: @week_start)
  end

  def create
    chore = current_household.chores.find(params[:chore_id])
    @week_start = params[:week_start].present? ? Date.parse(params[:week_start]) : Time.zone.today.beginning_of_week

    # find_or_initialize rather than a plain create: if this chore is somehow
    # already on the week's list (e.g. a due-soon card got dropped twice
    # before the first request finished), just move the existing row to
    # wherever it was just dropped instead of failing a uniqueness check.
    @weekly_chore = current_household.weekly_chores.find_or_initialize_by(chore: chore, week_start: @week_start)
    # A plain "Add to this week" click (no explicit day) fills in the first
    # day that doesn't already have a chore on it — every chore needs a day.
    @weekly_chore.scheduled_date = params[:scheduled_date].presence || WeeklyChore.first_available_day(current_household, @week_start)

    respond_to do |format|
      if @weekly_chore.save
        @weekly_chore.insert_at(params[:position].to_i) if params[:position].present?
        format.turbo_stream
        format.html { redirect_to weekly_chores_path(date: @week_start), notice: "Added \"#{chore.name}\" to this week." }
      else
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to weekly_chores_path(date: @week_start), alert: @weekly_chore.errors.full_messages.to_sentence }
      end
    end
  end

  # POST /weekly_chores/:id/move — drag-and-drop onto a different day in the
  # board. Mirrors TodosController#move.
  def move
    @week_start = @weekly_chore.week_start
    scheduled_date = params[:scheduled_date].presence && Date.parse(params[:scheduled_date])
    @weekly_chore.move_to_day!(scheduled_date, params[:position])

    head :ok
  end

  # POST /weekly_chores/reorder — same-column drag reorder. Mirrors
  # TodosController#reorder.
  def reorder
    scheduled_date = params[:scheduled_date].presence

    Array(params[:order]).each_with_index do |id, index|
      current_household.weekly_chores
                  .where(scheduled_date: scheduled_date, id: id)
                  .update_all(position: index + 1)
    end

    head :ok
  end

  def update
    @week_start = @weekly_chore.week_start

    if weekly_chore_params.key?(:completed)
      ActiveModel::Type::Boolean.new.cast(weekly_chore_params[:completed]) ? @weekly_chore.mark_complete! : @weekly_chore.mark_incomplete!
    else
      @weekly_chore.update(weekly_chore_params)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to weekly_chores_path(date: @week_start) }
    end
  end

  def destroy
    @week_start = @weekly_chore.week_start
    @chore = @weekly_chore.chore
    @weekly_chore.destroy!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to weekly_chores_path(date: @week_start) }
    end
  end

  private

  def set_weekly_chore
    @weekly_chore = current_household.weekly_chores.find(params[:id])
  end

  def week_start_from_params
    params[:date].present? ? Date.parse(params[:date]) : Time.zone.today.beginning_of_week
  end

  def weekly_chore_params
    params.require(:weekly_chore).permit(:assignee_id, :completed)
  end
end
