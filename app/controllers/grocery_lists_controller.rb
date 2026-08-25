class GroceryListsController < ApplicationController
  before_action :set_grocery_list, only: %i[show edit update destroy]
  before_action :set_date, only: [:index, :generate]

  def index
    @ingredient_families = [
      { color: 'mauve',      label: 'Protein' },
      { color: 'mist',       label: 'Produce' },
      { color: 'taupe',      label: 'Dairy' },
      { color: 'honey',      label: 'Grain' },
      { color: 'terracotta', label: 'Fat' },
      { color: 'mist',       label: 'Spices' }
    ]

    @grocery_lists = current_household.grocery_lists
                                 .where("week_of >= ?", @date)
                                 .where("week_of < ?", @date + 7)
                                 .includes(:ingredient)
                                 .joins(:ingredient)
                                 .order("ingredients.family ASC, ingredients.ingredient ASC")

    if params[:filter].present?
      @grocery_lists = @grocery_lists.where(ingredients: { family: params[:filter] })
    end
  end

  def generate
    meals = current_household.meals
                        .where("date >= ?", @date)
                        .where("date < ?", @date + 7)
                        .includes(recipe: { recipe_ingredients: { ingredient: :nutrition_fact } })

    current_household.grocery_lists
                .where("week_of >= ?", @date)
                .where("week_of < ?", @date + 7)
                .destroy_all

    ingredient_data = {}

    meals.each do |meal|
      multiplier = meal.servings_multiplier

      meal.recipe.recipe_ingredients.each do |recipe_ingredient|
        ingredient_id    = recipe_ingredient.ingredient_id
        ingredient       = recipe_ingredient.ingredient
        scaled_quantity  = recipe_ingredient.quantity.to_f * multiplier

        servings_needed = calculate_servings_needed_for(scaled_quantity, recipe_ingredient.unit, ingredient)

        units_needed = if ingredient.unit_servings.present? && ingredient.unit_servings > 0
                         (servings_needed / ingredient.unit_servings.to_f).ceil
                       else
                         1
                       end

        if ingredient_data[ingredient_id]
          ingredient_data[ingredient_id][:servings] += servings_needed
          if ingredient.unit_servings.present? && ingredient.unit_servings > 0
            ingredient_data[ingredient_id][:units] =
              (ingredient_data[ingredient_id][:servings] / ingredient.unit_servings.to_f).ceil
          end
          ingredient_data[ingredient_id][:meal_ids] << meal.id
        else
          ingredient_data[ingredient_id] = { servings: servings_needed, units: units_needed, meal_ids: [meal.id] }
        end
      end
    end

    ingredient_data.each do |ingredient_id, data|
      current_household.grocery_lists.create!(
        user: current_user,
        ingredient_id: ingredient_id,
        units: data[:units],
        meal_ids: data[:meal_ids].uniq,
        week_of: @date,
        checked: false,
        manually_adjusted: false
      )
    end

    redirect_to grocery_lists_path(date: @date),
                notice: "Grocery list generated for week of #{@date.strftime('%B %d, %Y')}"
  end

  def show; end
  def new; @grocery_list = GroceryList.new; end
  def edit; end

  def create
    @grocery_list = current_household.grocery_lists.build(grocery_list_params)
    @grocery_list.user = current_user

    respond_to do |format|
      if @grocery_list.save
        @grocery_list.broadcast_append_to(
          current_household, "grocery_lists",
          target: "grocery_lists",
          partial: "grocery_lists/grocery_list",
          locals: { grocery_list: @grocery_list }
        )
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully created." }
        format.json { render :show, status: :created, location: @grocery_list }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_grocery_list", partial: "grocery_lists/new", locals: { grocery_list: GroceryList.new }) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
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

  def destroy
    @ingredient_name = @grocery_list.ingredient.ingredient
    @grocery_list.destroy!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to grocery_lists_path, notice: "#{@ingredient_name} removed from list.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_grocery_list
    @grocery_list = current_household.grocery_lists.find(params.expect(:id))
    @units = @grocery_list.units
  end

  def set_date
    @date = Date.today.beginning_of_week
    @date = Date.parse(params[:date]) if params[:date].present?
  end

  def calculate_servings_needed_for(quantity, unit, ingredient)
    nutrition_fact = ingredient.nutrition_fact
    return 1 unless nutrition_fact&.serving_size.present?
    return 1 unless quantity&.positive?

    if unit == nutrition_fact.serving_unit
      quantity / nutrition_fact.serving_size
    else
      convert_units(quantity, unit, nutrition_fact.serving_size, nutrition_fact.serving_unit)
    end
  end

  def convert_units(quantity, from_unit, serving_size, serving_unit)
    conversions = {
      'g' => 1, 'kg' => 1000, 'oz' => 28.35, 'lb' => 453.59,
      'ml' => 1, 'l' => 1000, 'cup' => 236.59, 'tbsp' => 14.79,
      'tsp' => 4.93, 'fl oz' => 29.57, 'piece' => 1, 'unit' => 1
    }

    from_unit    = from_unit.to_s.downcase
    serving_unit = serving_unit.to_s.downcase
    from_base    = conversions[from_unit]
    to_base      = conversions[serving_unit]

    if from_base && to_base
      (quantity * from_base) / (serving_size * to_base)
    else
      quantity / serving_size
    end
  end

  def grocery_list_params
    params.expect(grocery_list: [:week_of, :ingredient_id, :units, :checked, :manually_adjusted])
  end
end