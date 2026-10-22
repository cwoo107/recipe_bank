require "json"

# Loads the public recipe library — ready-made recipes anyone can browse and
# save, so a new household isn't starting from an empty Recipes page — from
# a JSON file (db/recipe_library.json), for the recipes:import_library task:
#
#   import = Recipe::LibraryImport.new("db/recipe_library.json")
#   import.rows    # => [Row, …] — what would happen to each recipe, for review
#   import.apply!  # creates the missing recipes, each in its own transaction
#
# The recipes belong to a dedicated library account (LIBRARY_EMAIL, created
# on first apply) and its household, "HomemakersHaven Kitchen" — nobody
# logs into it, and its recipes stay out of every real household's own
# list. Each recipe is public, tagged with the household's default tags, and
# draws its ingredients from the shared catalog (Ingredient#copy_for), so
# load the catalog first: rake ingredients:import_catalog.
#
# File shape: { "recipes": [ { "title", "description", "servings",
# "tags": [..], "ingredients": [ { "name", "quantity", "unit", "optional" } ],
# "steps": [..] } ] }.
#
# Matched to the library by title, so the file can be extended and re-run:
#   - create:    not in the library yet.
#   - unchanged: already there, matching the file.
#   - update:    already there but different from the file — only with
#                refresh: true (REFRESH=1); otherwise it's left as is.
#   - invalid:   can't be imported as written (reasons given); skipped.
#
# A refresh rewrites the library's own copy in place — details, ingredient
# lines, steps and tags — keeping its id, so favorites and planned meals
# that point at it still work. Recipes households saved are their own
# copies and are never touched.
class Recipe::LibraryImport
  LIBRARY_EMAIL = ENV.fetch("LIBRARY_EMAIL", "kitchen@homemakershaven.invalid")
  LIBRARY_NAME  = "HomemakersHaven Kitchen".freeze

  Row = Struct.new(:title, :action, :data, :problems, :changes, keyword_init: true) do
    def create?  = action == :create
    def update?  = action == :update
    def invalid? = action == :invalid
  end

  def initialize(path, refresh: false)
    @path    = path
    @refresh = refresh
  end

  def recipes
    @recipes ||= Array(JSON.parse(File.read(@path))["recipes"])
  end

  def rows
    @rows ||= begin
      existing = library_user ? library_user.recipes.includes(:tags, :steps, recipe_ingredients: :ingredient).index_by(&:title) : {}
      recipes.map do |data|
        title    = data["title"].to_s.squish
        problems = problems_for(data)
        recipe   = existing[title]
        changes  = recipe ? differences(recipe, data) : []
        action   = if problems.any? then :invalid
                   elsif recipe.nil? then :create
                   elsif changes.any? && @refresh then :update
                   else :unchanged
                   end
        Row.new(title:, action:, data:, problems:, changes:)
      end
    end
  end

  # Creates every :create row and, when refreshing, rewrites every :update
  # row; returns how many recipes were written.
  def apply!
    to_write = rows.select { |row| row.create? || row.update? }
    return 0 if to_write.empty?

    user = ensure_library_account!
    to_write.each do |row|
      row.create? ? create_recipe!(user, row.data) : refresh_recipe!(user, user.recipes.find_by!(title: row.title), row.data)
    end
    to_write.size
  end

  def library_user
    @library_user ||= User.find_by(email: LIBRARY_EMAIL)
  end

  private

  def problems_for(data)
    problems = []
    problems << "no title" if data["title"].to_s.strip.empty?
    problems << "no steps" if Array(data["steps"]).empty?

    lines = Array(data["ingredients"])
    problems << "no ingredients" if lines.empty?
    missing = lines.map { |line| line["name"].to_s }.reject { |name| catalog_names.include?(name.squish.downcase) }
    problems << "not in the ingredient catalog: #{missing.uniq.join(', ')}" if missing.any?

    bad_units = lines.map { |line| line["unit"].to_s }.reject { |unit| unit.empty? || RecipeIngredient::UNITS.include?(unit) }
    problems << "units the picker doesn't offer: #{bad_units.uniq.join(', ')}" if bad_units.any?
    problems
  end

  def catalog_names
    @catalog_names ||= Ingredient.catalog.pluck(:ingredient).map { |name| name.squish.downcase }.to_set
  end

  # The library's own login and household — created once, with an unusable
  # random password (the address can't receive mail, so no reset either).
  def ensure_library_account!
    return library_user if library_user

    User.transaction do
      user = User.create!(email: LIBRARY_EMAIL, password: SecureRandom.base58(32), household_family_name: LIBRARY_NAME)
      user.household.household_members.find_by!(user:).update!(name: LIBRARY_NAME)
      @library_user = user
    end
  end

  def create_recipe!(user, data)
    Recipe.transaction do
      recipe = user.recipes.create!(
        title:       data["title"].to_s.squish,
        description: data["description"],
        servings:    data["servings"],
        visibility:  "public"
      )
      fill!(user, recipe, data)
    end
  end

  # The library's own copy brought in line with the file, keeping its id.
  def refresh_recipe!(user, recipe, data)
    Recipe.transaction do
      recipe.update!(description: data["description"], servings: data["servings"], visibility: "public")
      recipe.recipe_ingredients.destroy_all
      recipe.steps.destroy_all
      recipe.recipe_tags.destroy_all
      fill!(user, recipe.reload, data)
    end
  end

  def fill!(user, recipe, data)
    household = user.household

    Array(data["ingredients"]).each do |line|
      ingredient = Ingredient.find_or_initialize_for(household, line["name"], created_by: user)
      ingredient.save! if ingredient.new_record?
      recipe.recipe_ingredients.create!(ingredient:, quantity: line["quantity"], unit: line["unit"].presence,
                                        optional: line["optional"] == true)
    end

    # In order — each new step lands at the end (Step#set_position).
    Array(data["steps"]).each { |step| recipe.steps.create!(content: step) }

    recipe.tags << household.tags.where(tag: Array(data["tags"]))
  end

  # What differs between the library's copy and the file, for review.
  def differences(recipe, data)
    changes = []
    changes << "description" if recipe.description.to_s != data["description"].to_s
    changes << "servings #{recipe.servings} → #{data['servings']}" if recipe.servings != data["servings"]

    have = recipe.recipe_ingredients.map { |line| line_key(line.ingredient&.ingredient, line.quantity, line.unit, line.optional) }.sort
    want = Array(data["ingredients"]).map { |line| line_key(line["name"], line["quantity"], line["unit"], line["optional"] == true) }.sort
    changes << "ingredients" if have != want

    steps = recipe.steps.sort_by(&:position).map { |step| step.content.to_plain_text.squish }
    changes << "steps" if steps != Array(data["steps"]).map { |step| step.to_s.squish }

    changes << "tags" if recipe.tags.map(&:tag).sort != (Array(data["tags"]) & Tag::DEFAULTS.map(&:first)).sort
    changes
  end

  def line_key(name, quantity, unit, optional)
    [ name.to_s.squish.downcase, quantity.to_f.round(3), unit.to_s, optional ? 1 : 0 ]
  end
end
