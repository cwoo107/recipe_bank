require "prawn"

# Every recipe the household's members have created, as one PDF the owner
# can download and keep — whether or not the household is still subscribed.
# A cover, a contents page grouped by who created each recipe (owner
# first), then one recipe per page. Built in memory, never stored.
#
#   RecipeBookPdf.new(household:).render
#
# Laid out twice: the first pass finds the page each recipe lands on, the
# second prints those numbers in the contents. Contents rows are one line
# each (long titles are cut short), so both passes paginate the same way.
class RecipeBookPdf
  include Prawn::View
  include PdfBasics

  MARGIN       = [ 64, 48, 56, 48 ].freeze
  CONTENTS_ROW = 16

  def initialize(household:)
    @household = household
  end

  def document
    @document ||= Prawn::Document.new(
      page_size: "LETTER",
      margin: MARGIN,
      info: { Title: "Recipes — #{@household.family_name}", Creator: "HomemakersHaven" }
    )
  end

  def render
    starts = compose({})
    @document = nil
    compose(starts)
    bookmarks(starts)
    document.render
  end

  def filename
    "#{@household.family_name.parameterize.presence || 'household'}-recipes-#{Date.current.iso8601}.pdf"
  end

  # [[author name, recipes], …] — household members in the household's own
  # order (owner first), each one's recipes by title.
  def recipes_by_author
    @recipes_by_author ||= begin
      recipes = Recipe.for_household(@household)
                      .includes(:tags, steps: :rich_text_content, recipe_ingredients: :ingredient)
                      .sort_by { |recipe| recipe.title.to_s.downcase }
                      .group_by(&:user_id)

      @household.people.filter_map do |member|
        mine = recipes.delete(member.user_id) if member.user_id
        [ member.name.presence || member.user.email, mine ] if mine
      end
    end
  end

  def recipe_count
    recipes_by_author.sum { |_, recipes| recipes.size }
  end

  private

  # Lays the whole book out; returns { recipe id => the page it starts on }.
  def compose(page_numbers)
    register_fonts
    font SANS
    fill_color INK

    cover_page
    start_new_page
    contents_pages(page_numbers)

    starts = {}
    recipes_by_author.each do |author, recipes|
      recipes.each do |recipe|
        start_new_page
        starts[recipe.id] = page_number
        recipe_page(recipe, author)
      end
    end

    page_furniture
    starts
  end

  def cover_page
    move_down 200
    font(SERIF) { text "Recipes", size: 48, color: SAGE_DARK, align: :center }
    move_down 4
    text clean(@household.display_name.upcase_first), size: 14, align: :center
    move_down 10
    text "#{recipe_count} #{'recipe'.pluralize(recipe_count)}  ·  Exported #{Date.current.strftime('%B %-d, %Y')}",
         size: 10, color: MUTED, align: :center
  end

  def contents_pages(page_numbers)
    font(SERIF) { text "Contents", size: 22, color: SAGE_DARK }
    move_down 10

    if recipes_by_author.empty?
      text "No recipes yet.", size: 10, color: MUTED, style: :italic
      return
    end

    recipes_by_author.each do |author, recipes|
      start_new_page if cursor < CONTENTS_ROW * 3
      move_down 8
      contents_row(author, nil, style: :bold, size: 11)
      stroke_color RULE
      stroke_horizontal_rule
      move_down 4

      recipes.each do |recipe|
        start_new_page if cursor < CONTENTS_ROW
        contents_row(recipe.title, page_numbers.fetch(recipe.id, 999))
      end
    end
  end

  def contents_row(label, number, style: :normal, size: 10)
    top = cursor
    text_box clean(label), at: [ 0, top ], width: bounds.width - 48, height: CONTENTS_ROW,
             size:, style:, single_line: true, overflow: :truncate
    if number
      text_box number.to_s, at: [ bounds.width - 40, top ], width: 40, height: CONTENTS_ROW,
               size:, align: :right, color: MUTED
    end
    move_down CONTENTS_ROW
  end

  def recipe_page(recipe, author)
    font(SERIF) { text clean(recipe.title), size: 22, color: INK }
    details = [ "From #{author}", ("Serves #{recipe.servings}" if recipe.servings),
                recipe.tags.map(&:tag).compact_blank.join(", ").presence ]
    text clean(details.compact.join("  ·  ")), size: 9, color: MUTED

    if recipe.description.present?
      move_down 8
      text clean(recipe.description), size: 10, leading: 1.5
    end

    move_down 12
    recipe_ingredients_and_steps(recipe)
  end

  # PDF bookmarks: a section per person, a link per recipe.
  def bookmarks(starts)
    groups = recipes_by_author.map do |author, recipes|
      [ clean(author), recipes.map { |recipe| [ clean(recipe.title), starts[recipe.id] ] } ]
    end

    outline.define do
      page destination: 2, title: "Contents"
      groups.each do |author, entries|
        section(author, destination: entries.first.last) do
          entries.each { |title, number| page destination: number, title: }
        end
      end
    end
  end

  # Brand + household along the top and page numbers at the bottom, on every
  # page but the cover.
  def page_furniture
    after_cover = ->(page) { page > 1 }
    repeat(after_cover) do
      canvas do
        fill_color MUTED
        text_box clean("HomemakersHaven  ·  #{@household.family_name}  ·  Recipes"),
                 at: [ 48, bounds.top - 28 ], width: bounds.width - 96, size: 8
      end
    end
    number_pages "<page>", at: [ bounds.right - 120, -24 ], width: 120, align: :right, size: 8, color: MUTED,
                 page_filter: after_cover, start_count_at: 2
    fill_color INK
  end
end
