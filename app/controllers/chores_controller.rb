class ChoresController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: :index
  before_action :set_chore, only: %i[edit update destroy]

  def index
    @chores = current_household.chores.ordered.includes(:assignee, :chore_category, :chore_tasks)
    @categories = current_household.chore_categories.ordered
  end

  def new
    categories = current_household.chore_categories
    default_category = categories.find_by(id: params[:chore_category_id]) || categories.find_by(name: "Chores") || categories.ordered.first
    @chore = current_household.chores.new(chore_category: default_category)
  end

  def edit
  end

  def create
    @chore = current_household.chores.new(chore_params.except(:default_weekday))

    if @chore.save
      reschedule_from_params
      redirect_to safe_return_to || chores_path, notice: "Chore was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Handles both the full edit form (board "view details" dialog, edit page)
  # and the Manage Chores inline editor, which posts inline=1 and gets its
  # row refreshed in place instead of a redirect.
  def update
    saved = @chore.update(chore_params.except(:default_weekday))
    reschedule_from_params if saved

    if params[:inline].present?
      render :refresh_row, formats: :turbo_stream, status: saved ? :ok : :unprocessable_entity
    elsif saved
      # An edit that started somewhere else (return_to) lands back there
      # rather than on the Manage Chores page.
      redirect_to safe_return_to || chores_path, notice: "Chore was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @chore.destroy!
    redirect_to chores_path, notice: "Chore was successfully deleted.", status: :see_other
  end

  private

  def set_chore
    @chore = current_household.chores.find(params[:id])
  end

  def chore_params
    permitted = scoped_assignee_params(params.require(:chore).permit(:name, :description, :frequency, :assignee_id, :chore_category_id, :default_weekday))
    # Only this household's categories — anything else is quietly dropped
    # rather than surfacing another household's record.
    if permitted[:chore_category_id].present? && !current_household.chore_categories.exists?(permitted[:chore_category_id])
      permitted.delete(:chore_category_id)
    end
    permitted
  end

  # Picking a day on Manage Chores applies from this week forward, like the
  # board's "going forward" move. Ignored for chores that aren't weekly or
  # biweekly (they don't have a remembered day).
  def reschedule_from_params
    return unless chore_params.key?(:default_weekday) && @chore.recurring?

    weekday = chore_params[:default_weekday].presence&.to_i
    @chore.reschedule_forward!(weekday, from_week: Date.current.beginning_of_week)
  end

  # Only ever redirect to a path within this app — params[:return_to] is
  # user-suppliable, so an absolute/external URL is rejected outright.
  def safe_return_to
    return_to = params[:return_to]
    return nil if return_to.blank?

    uri = URI.parse(return_to) rescue nil
    return nil unless uri && uri.host.nil? && return_to.start_with?("/")

    return_to
  end
end
