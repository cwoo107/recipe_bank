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
  def available_component_recipes(recipe, household)
    Recipe.for_household(household)
          .where.not(id: recipe.id)
          .where.not(id: recipe.component_recipes.select(:id))
          .order(:title)
          .reject { |candidate| candidate.depends_on?(recipe) }
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
