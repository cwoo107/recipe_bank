# Picks the recipes that lead everyone's public browse list. Only public
# recipes can be featured — a private one would never show up there anyway.
class Admin::FeaturedRecipesController < Admin::BaseController
  SEARCH_LIMIT = 25

  def index
    @featured = Recipe.featured.includes(:user).order(:title)
    @query    = params[:q].to_s.strip

    if @query.present?
      term = "%#{Recipe.sanitize_sql_like(@query.downcase)}%"
      @results = Recipe.publicly_visible.where(featured: false)
                       .where("LOWER(recipes.title) LIKE ?", term)
                       .includes(:user).order(:title).limit(SEARCH_LIMIT)
    end
  end

  def create
    recipe = Recipe.publicly_visible.find(params[:recipe_id])
    recipe.update!(featured: true)
    redirect_to admin_featured_recipes_path, notice: "Featured \"#{recipe.title}\".", status: :see_other
  end

  def destroy
    recipe = Recipe.featured.find(params[:id])
    recipe.update!(featured: false)
    redirect_to admin_featured_recipes_path, notice: "\"#{recipe.title}\" is no longer featured.", status: :see_other
  end
end
