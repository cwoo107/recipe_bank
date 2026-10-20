# The household's recipe tags — the Recipe tags tab on the Recipes page.
class TagsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: %i[index show]
  before_action :set_tag, only: %i[show edit update destroy]

  def index
    @tags = current_household.tags.ordered.includes(:recipes)
  end

  def show
  end

  def new
    @tag = current_household.tags.build
  end

  def edit
  end

  def create
    @tag = current_household.tags.build(tag_params.merge(user: current_user))

    if @tag.save
      redirect_to tags_path, notice: "Tag was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "Tag was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tag.destroy!
    redirect_to tags_path, notice: "Tag was successfully deleted.", status: :see_other
  end

  private

  def set_tag
    @tag = current_household.tags.find(params.expect(:id))
  end

  def tag_params
    params.expect(tag: [:tag, :color])
  end
end