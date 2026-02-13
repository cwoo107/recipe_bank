class GroceryListsController < ApplicationController
  before_action :set_grocery_list, only: %i[ show edit update destroy ]
  before_action :set_date, only: [:index, :generate]

  # GET /grocery_lists or /grocery_lists.json
  def index
    @grocery_lists = GroceryList.where("week_of >= ?", @date)
                                .where('week_of < ?', @date + 7)
                                .includes(:ingredient)
                                .joins(:ingredient)
                                .order('ingredients.family ASC, ingredients.ingredient ASC')
  end

  def generate
    # Get all meals for the week
    meals = Meal.where("date >= ?", @date)
                .where("date < ?", @date + 7)
                .includes(recipe: { recipe_ingredients: { ingredient: :nutrition_fact } })

    # Clear existing grocery lists for this week
    GroceryList.where("week_of >= ?", @date)
               .where('week_of < ?', @date + 7)
               .destroy_all

    # Group ingredients by ingredient_id and aggregate
    ingredient_data = {}

    meals.each do |meal|
      meal.recipe.recipe_ingredients.each do |recipe_ingredient|
        ingredient_id = recipe_ingredient.ingredient_id
        ingredient = recipe_ingredient.ingredient

        # Calculate servings needed for this recipe ingredient
        servings_needed = calculate_servings_needed(recipe_ingredient, ingredient)

        # Calculate units needed (how many store units to buy)
        units_needed = if ingredient.unit_servings.present? && ingredient.unit_servings > 0
                         (servings_needed / ingredient.unit_servings.to_f).ceil
                       else
                         1 # Default to 1 unit if no serving data
                       end

        if ingredient_data[ingredient_id]
          ingredient_data[ingredient_id][:servings] += servings_needed
          ingredient_data[ingredient_id][:units] = (ingredient_data[ingredient_id][:servings] / ingredient.unit_servings.to_f).ceil if ingredient.unit_servings.present? && ingredient.unit_servings > 0
          ingredient_data[ingredient_id][:meal_ids] << meal.id
        else
          ingredient_data[ingredient_id] = {
            servings: servings_needed,
            units: units_needed,
            meal_ids: [meal.id]
          }
        end
      end
    end

    # Create grocery list items
    ingredient_data.each do |ingredient_id, data|
      GroceryList.create(
        ingredient_id: ingredient_id,
        units: data[:units],
        meal_ids: data[:meal_ids].uniq,
        week_of: @date,
        checked: false,
        manually_adjusted: false
      )
    end

    redirect_to grocery_lists_path(date: @date), notice: "Grocery list generated for week of #{@date.strftime('%B %d, %Y')}"
  end

  # GET /grocery_lists/1 or /grocery_lists/1.json
  def show
  end

  # GET /grocery_lists/new
  def new
    @grocery_list = GroceryList.new
  end

  # GET /grocery_lists/1/edit
  def edit
  end

  # POST /grocery_lists or /grocery_lists.json
  def create
    @grocery_list = GroceryList.new(grocery_list_params)

    respond_to do |format|
      if @grocery_list.save
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully created." }
        format.json { render :show, status: :created, location: @grocery_list }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /grocery_lists/1 or /grocery_lists/1.json
  def update
    puts grocery_list_params[:units]
    puts @units
    if grocery_list_params[:units].to_i != @units
      @grocery_list.manually_adjusted = true
    end
    respond_to do |format|
      if @grocery_list.update(grocery_list_params)
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "grocery_list_#{@grocery_list.id}",
            partial: "grocery_lists/grocery_list",
            locals: { grocery_list: @grocery_list }
          )
        end
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @grocery_list }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /grocery_lists/1 or /grocery_lists/1.json
  def destroy
    @grocery_list.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("grocery_list_#{@grocery_list.id}")
      end
      format.html { redirect_to grocery_lists_path, notice: "Grocery list was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_grocery_list
    @grocery_list = GroceryList.find(params.expect(:id))
    @units = @grocery_list.units
  end

  def set_date
    @date = Date.today.beginning_of_week
    if params[:date].present?
      @date = Date.parse(params[:date])
    end
  end

  def calculate_servings_needed(recipe_ingredient, ingredient)
    nutrition_fact = ingredient.nutrition_fact
    return 1 unless nutrition_fact&.serving_size.present?

    if recipe_ingredient.unit == nutrition_fact.serving_unit
      recipe_ingredient.quantity / nutrition_fact.serving_size
    else
      convert_units(recipe_ingredient.quantity, recipe_ingredient.unit,
                    nutrition_fact.serving_size, nutrition_fact.serving_unit)
    end
  end

  def convert_units(quantity, from_unit, serving_size, serving_unit)
    conversions = {
      'g' => 1, 'kg' => 1000, 'oz' => 28.35, 'lb' => 453.59,
      'ml' => 1, 'l' => 1000, 'cup' => 236.59, 'tbsp' => 14.79,
      'tsp' => 4.93, 'fl oz' => 29.57, 'piece' => 1, 'unit' => 1
    }

    from_unit = from_unit.to_s.downcase
    serving_unit = serving_unit.to_s.downcase
    from_base = conversions[from_unit]
    to_base = conversions[serving_unit]

    if from_base && to_base
      base_quantity = quantity * from_base
      base_serving = serving_size * to_base
      base_quantity / base_serving
    else
      quantity / serving_size
    end
  end

  # Only allow a list of trusted parameters through.
  def grocery_list_params
    params.expect(grocery_list: [ :week_of, :ingredient_id, :units, :checked, :manually_adjusted ])
  end
end