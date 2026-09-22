module RecipesHelper
  # The index keeps several bits of state in the query string (which scope is
  # showing, tag filter, search term, sort). Every link out of the list has to
  # carry them forward or the user loses their place.
  def recipes_list_path(overrides = {})
    current = params.permit(:scope, :filter, :query, :sort, :direction).to_h.symbolize_keys
    recipes_path(current.merge(overrides).compact_blank)
  end

  def recipes_sort_path(column)
    flipped = params[:sort] == column && params[:direction] == "asc" ? "desc" : "asc"
    recipes_list_path(sort: column, direction: flipped)
  end
end
