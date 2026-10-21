require "prawn"

# One recipe, printed from its page: title, servings and tags, the
# description, then its ingredients (by family) and steps — set like a
# recipe in the recipe book (RecipeBookPdf) and the week plan's recipes
# page. Built in memory, never stored.
#
#   RecipePdf.new(recipe:).render
class RecipePdf
  include Prawn::View
  include PdfBasics

  MARGIN = [ 64, 48, 56, 48 ].freeze

  def initialize(recipe:)
    @recipe = recipe
  end

  def document
    @document ||= Prawn::Document.new(
      page_size: "LETTER",
      margin: MARGIN,
      info: { Title: clean(@recipe.title), Creator: "HomemakersHaven" }
    )
  end

  def render
    register_fonts
    font SANS
    fill_color INK

    font(SERIF) { text clean(@recipe.title), size: 26, color: SAGE_DARK }
    details = [ ("Serves #{@recipe.servings}" if @recipe.servings),
                @recipe.tags.map(&:tag).compact_blank.join(", ").presence ]
    text(clean(details.compact.join("  ·  ")), size: 9, color: MUTED) if details.any?

    if @recipe.description.present?
      move_down 8
      text clean(@recipe.description), size: 10, leading: 1.5
    end

    move_down 14
    recipe_ingredients_and_steps(@recipe)

    page_furniture
    document.render
  end

  def filename
    "#{@recipe.title.parameterize.presence || 'recipe'}.pdf"
  end

  private

  def page_furniture
    repeat(:all) do
      canvas do
        fill_color MUTED
        text_box "HomemakersHaven", at: [ 48, bounds.top - 28 ], width: bounds.width - 96, size: 8
      end
    end
    number_pages "Page <page> of <total>", at: [ bounds.right - 120, -24 ], width: 120, align: :right, size: 8, color: MUTED
    fill_color INK
  end
end
