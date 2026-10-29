class GroceryListsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: %i[index show]
  before_action :set_grocery_list, only: %i[show edit update destroy]
  before_action :set_date, only: [:index, :generate, :check_all, :destroy_checked]

  def index
    @grocery_lists = shown_grocery_lists
                       .includes(:ingredient)
                       # Categories in the Ingredients page's order, then A–Z;
                       # notes (no ingredient) come last, oldest first.
                       .order(Ingredient.family_order_sql, "ingredients.ingredient ASC", :id)

    # The categories with something on this week's list — the only filters
    # worth offering. Not narrowed by the current filter, so the others stay
    # there to switch to.
    @list_families = GroceryList.families_for_week(current_household, @date)

    # What each line is for (the "used in N meals" hover), worked out once
    # for the whole list.
    @grocery_uses = GroceryList::Breakdown.uses_by_ingredient(
      current_household.meals.where(id: @grocery_lists.flat_map(&:meal_ids).uniq).includes(:recipe)
    )

    # Second tab: what's marked Restock on the restock checklist, by store.
    @restock_list = RestockItem.shopping_list(current_household)
    @active_list  = params[:list] == "restock" ? "restock" : "groceries"
  end

  def generate
    meals = current_household.meals
                        .where("date >= ?", @date)
                        .where("date < ?", @date + 7)
                        .where.not(recipe_id: nil) # note-only meals have nothing to buy
                        .includes(recipe: { recipe_ingredients: { ingredient: :nutrition_fact } })

    # Notes aren't from the meal plan, so they stay.
    current_household.grocery_lists
                .where("week_of >= ?", @date)
                .where("week_of < ?", @date + 7)
                .where.not(ingredient_id: nil)
                .destroy_all

    ingredient_data = {}

    meals.each do |meal|
      multiplier = meal.servings_multiplier

      # all_ingredients covers component recipes as well — a meal built on the
      # chicken still needs the sauce's lemons on the list.
      meal.recipe.all_ingredients.each do |line|
        ingredient_id    = line.ingredient_id
        ingredient       = line.ingredient
        next unless ingredient
        next if ingredient.not_shopped? # tap water, not something to buy

        scaled_quantity  = line.quantity * multiplier

        servings_needed = calculate_servings_needed_for(scaled_quantity, line.unit, ingredient)

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
  # The "Add to list" dialog on the list page, for the week being viewed.
  def new
    week = params[:week].present? ? Date.parse(params[:week]).beginning_of_week : Time.zone.today.beginning_of_week
    @grocery_list = GroceryList.new(week_of: week)
  end
  def edit; end

  # Adds a picked ingredient, a typed name that isn't in the household's
  # ingredients yet (added to them, like the recipe page's picker — see
  # RecipeIngredientsController#create), or — from the "Make a Note" tab — a
  # note.
  def create
    @grocery_list = current_household.grocery_lists.build(grocery_list_params)
    @grocery_list.user = current_user
    added = nil # :copied or :created, when the line brings a new ingredient

    note_entry = params.dig(:grocery_list, :entry) == "note"
    if note_entry
      @grocery_list.ingredient_id = nil
      @grocery_list.units = nil
    else
      @grocery_list.note = nil
    end

    saved = GroceryList.transaction do
      unless note_entry
        # The household's own ingredient, or a default (catalog) one copied
        # in — never another household's.
        if (picked_id = @grocery_list.ingredient_id)
          @grocery_list.ingredient = Ingredient.pick_for(current_household, picked_id, user: current_user)
          added = :copied if @grocery_list.ingredient&.previously_new_record?
        end

        if @grocery_list.ingredient_id.blank? && (typed = typed_ingredient)
          added = typed.new_record? ? :created : (:copied if typed.previously_new_record?)
          @grocery_list.ingredient = typed
        end
      end

      # Saves a new ingredient first; a failed line rolls back a catalog copy.
      @grocery_list.save || raise(ActiveRecord::Rollback)
    end

    respond_to do |format|
      if saved
        new_ingredient = @grocery_list.ingredient
        IngredientEnrichmentJob.perform_later(new_ingredient.id) if added && new_ingredient.needs_enrichment?

        @grocery_list.broadcast_append_to(
          current_household, "grocery_lists",
          target: "grocery_lists",
          partial: "grocery_lists/grocery_list",
          locals: { grocery_list: @grocery_list }
        )
        GroceryList.broadcast_family_filters(current_household, @grocery_list.week_of)
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully created." }
        format.json { render :show, status: :created, location: @grocery_list }
        format.turbo_stream do
          streams = [ turbo_stream.replace("new_grocery_list", partial: "grocery_lists/new",
                                           locals: { grocery_list: GroceryList.new(week_of: @grocery_list.week_of) }) ]
          if added
            notice = added == :copied ? "Added #{new_ingredient.ingredient} to your ingredients, with its cost and nutrition." :
                                        "Added #{new_ingredient.ingredient} to your ingredients. We're estimating its cost and nutrition now."
            streams << turbo_stream.update("flash", partial: "shared/flash", locals: { notice: })
          end
          render turbo_stream: streams
        end
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("new_grocery_list", partial: "grocery_lists/new", locals: { grocery_list: @grocery_list }),
                 status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    if grocery_list_params.key?(:units) && grocery_list_params[:units].to_i != @units
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

  # PATCH /grocery_lists/check_all — "Select all": ticks off everything
  # shown (this week, under the current filter); with checked=false, "Unselect
  # all" unticks it. Back to the list, which refreshes in place.
  def check_all
    shown_grocery_lists.update_all(checked: params[:checked] != "false", updated_at: Time.current)
    redirect_back_or_to grocery_lists_path(date: @date), status: :see_other
  end

  # DELETE /grocery_lists/destroy_checked — "Delete all checked items": takes
  # what's ticked off (of what's shown) off the list.
  def destroy_checked
    checked = shown_grocery_lists.where(checked: true)
    count = checked.size
    checked.destroy_all

    redirect_back_or_to grocery_lists_path(date: @date),
                        notice: "#{count} checked #{'item'.pluralize(count)} removed from the list.", status: :see_other
  end

  def destroy
    @ingredient_name = @grocery_list.title
    @grocery_list.destroy!
    GroceryList.broadcast_family_filters(current_household, @grocery_list.week_of)

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

  # The list as the page shows it: the week, under the category filter if
  # there is one.
  def shown_grocery_lists
    lists = current_household.grocery_lists.where(week_of: @date...(@date + 7)).left_joins(:ingredient)
    params[:filter].present? ? lists.where(ingredients: { family: params[:filter] }) : lists
  end

  def set_date
    @date = (params[:date].present? ? Date.parse(params[:date]) : Time.zone.today).beginning_of_week
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
    params.expect(grocery_list: [:week_of, :ingredient_id, :note, :units, :checked, :manually_adjusted])
  end

  # What was typed into the ingredient picker when nothing was picked.
  def typed_ingredient
    name = params.dig(:grocery_list, :new_ingredient_name).to_s.squish
    Ingredient.find_or_initialize_for(current_household, name, created_by: current_user) if name.present?
  end
end