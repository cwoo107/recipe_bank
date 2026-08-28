class ChoresController < ApplicationController
  before_action :set_chore, only: %i[edit update destroy]

  def index
    @chores = current_household.chores.ordered.includes(:assignee)
  end

  def new
    @chore = current_household.chores.new
  end

  def edit
  end

  def create
    @chore = current_household.chores.new(chore_params)

    if @chore.save
      redirect_to chores_path, notice: "Chore was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @chore.update(chore_params)
      # Editing from the "view chore" dialog on the Chore Chart board should
      # land back on the board (with the change reflected), not the Manage
      # Chores page — see weekly_chores/_chore_details_dialog.html.erb.
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
    params.require(:chore).permit(:name, :description, :frequency, :assignee_id)
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
