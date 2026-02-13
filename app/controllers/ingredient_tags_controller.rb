class IngredientTagsController < ApplicationController
  before_action :set_ingredient_tag, only: %i[ show edit update destroy ]

  # GET /ingredient_tags or /ingredient_tags.json
  def index
    @ingredient_tags = IngredientTag.all
  end

  # GET /ingredient_tags/1 or /ingredient_tags/1.json
  def show
  end

  # GET /ingredient_tags/new
  def new
    @ingredient_tag = IngredientTag.new
  end

  # GET /ingredient_tags/1/edit
  def edit
  end

  # POST /ingredient_tags or /ingredient_tags.json
  def create
    @ingredient_tag = IngredientTag.new(ingredient_tag_params)

    respond_to do |format|
      if @ingredient_tag.save
        format.html { redirect_to @ingredient_tag, notice: "Ingredient tag was successfully created." }
        format.json { render :show, status: :created, location: @ingredient_tag }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @ingredient_tag.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /ingredient_tags/1 or /ingredient_tags/1.json
  def update
    respond_to do |format|
      if @ingredient_tag.update(ingredient_tag_params)
        format.html { redirect_to @ingredient_tag, notice: "Ingredient tag was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @ingredient_tag }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @ingredient_tag.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /ingredient_tags/1 or /ingredient_tags/1.json
  def destroy
    @ingredient_tag.destroy!

    respond_to do |format|
      format.html { redirect_to ingredient_tags_path, notice: "Ingredient tag was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_ingredient_tag
      @ingredient_tag = IngredientTag.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def ingredient_tag_params
      params.expect(ingredient_tag: [ :ingredient_id, :tag_id ])
    end
end
