class ChoreCategoriesController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_chore_category, only: %i[edit update destroy]

  # new/edit render into a dialog on the Chore Chart board (see
  # weekly_chores/_category_label.html.erb); create/update/destroy land back
  # on whichever page they came from (return_to), defaulting to Manage Chores.
  def new
    @chore_category = current_household.chore_categories.new
  end

  def edit; end

  def create
    @chore_category = current_household.chore_categories.new(chore_category_params)

    if @chore_category.save
      redirect_to return_path, notice: "Added the \"#{@chore_category.name}\" category.", status: :see_other
    else
      redirect_to return_path, alert: @chore_category.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    if @chore_category.update(chore_category_params)
      redirect_to return_path, notice: "Category renamed.", status: :see_other
    else
      redirect_to return_path, alert: @chore_category.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # POST /chore_categories/reorder — drag-reordering the board's rows.
  # Mirrors WeeklyChoresController#reorder.
  def reorder
    ids = Array(params[:order]).map(&:to_i)
    categories = current_household.chore_categories.where(id: ids).index_by(&:id)

    ChoreCategory.transaction do
      ids.each_with_index do |id, index|
        categories[id]&.update_column(:position, index + 1)
      end
    end

    head :ok
  end

  # Its chores stay, just uncategorized (ChoreCategory has_many :chores, dependent: :nullify).
  def destroy
    @chore_category.destroy!
    redirect_to return_path, notice: "Deleted the \"#{@chore_category.name}\" category.", status: :see_other
  end

  private

  def set_chore_category
    @chore_category = current_household.chore_categories.find(params[:id])
  end

  def chore_category_params
    params.require(:chore_category).permit(:name)
  end

  # Only ever redirect to a path within this app — params[:return_to] is
  # user-suppliable, so an absolute/external URL is rejected outright.
  def return_path
    return_to = params[:return_to].to_s
    uri = URI.parse(return_to) rescue nil
    return chores_path unless uri && uri.host.nil? && return_to.start_with?("/")

    return_to
  end
end
