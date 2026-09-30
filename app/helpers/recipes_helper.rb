module RecipesHelper
  # The index keeps several bits of state in the query string (which scope is
  # showing, tag filter, search term, sort). Every link out of the list has to
  # carry them forward or the user loses their place.
  def recipes_list_path(overrides = {})
    current = params.permit(:scope, :filter, :query, :sort, :direction).to_h.symbolize_keys
    recipes_path(current.merge(overrides).compact_blank)
  end

  # Recipes that can be attached to `recipe` as components: the household's
  # own, minus this recipe, minus ones already attached, minus anything that
  # already uses this recipe (which would close a loop). The last filter walks
  # each candidate's component tree, so it costs a query per candidate.
  # include_public: true widens the pool from the household's own recipes to
  # public ones too (the same pool the meal planner browses —
  # Recipe.browsable_by_household); the picker hides those until its
  # "Also browse public recipes" toggle is on.
  #
  # Only a recipe that has components of its own can already use this one,
  # so the (query-per-recipe) circularity walk is skipped for the rest —
  # which is most of them, and matters once public recipes are included.
  def available_component_recipes(recipe, household, include_public: false)
    pool = include_public ? Recipe.browsable_by_household(household) : Recipe.for_household(household)
    candidates = pool.where.not(id: recipe.id)
                     .where.not(id: recipe.component_recipes.select(:id))
                     .order(:title)
                     .to_a
    with_components = RecipeComponent.where(parent_recipe_id: candidates.map(&:id)).distinct.pluck(:parent_recipe_id).to_set

    candidates.reject { |candidate| with_components.include?(candidate.id) && candidate.depends_on?(recipe) }
  end

  # Every step inside a component recipe, including the ones it pulls in
  # itself, flattened in reading order and paired with the recipe each came
  # from so nested sections can be labelled.
  def component_step_lines(component_recipe)
    component_recipe.sections.flat_map do |section|
      section.own_steps.map { |step| [section, step] }
    end
  end

  def recipes_sort_path(column)
    flipped = params[:sort] == column && params[:direction] == "asc" ? "desc" : "asc"
    recipes_list_path(sort: column, direction: flipped)
  end
end
