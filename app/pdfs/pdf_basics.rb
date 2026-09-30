require "prawn"

# What the app's PDFs share: the brand colors, the app's own typefaces —
# Instrument Serif for headings, Inter for text — embedded from vendor/fonts
# (Prawn subsets them, so only the letters used end up in the file), and how
# a recipe's ingredients and steps are set. Mixed into Prawn::View classes
# (WeekPlanPdf, RecipeBookPdf).
module PdfBasics
  SAGE       = "5f734c".freeze
  SAGE_DARK  = "3f4d34".freeze
  SAGE_LIGHT = "e8ede3".freeze
  INK        = "2f3027".freeze
  MUTED      = "6f705f".freeze
  RULE       = "d4ddc9".freeze

  FONT_DIR = Rails.root.join("vendor/fonts")
  SERIF    = "Instrument Serif".freeze
  SANS     = "Inter".freeze

  private

  def register_fonts
    font_families.update(
      SANS => {
        normal: FONT_DIR.join("Inter-Regular.ttf").to_s,
        italic: FONT_DIR.join("Inter-Italic.ttf").to_s,
        bold:   FONT_DIR.join("Inter-SemiBold.ttf").to_s
      },
      SERIF => {
        normal: FONT_DIR.join("InstrumentSerif-Regular.ttf").to_s,
        italic: FONT_DIR.join("InstrumentSerif-Italic.ttf").to_s,
        bold:   FONT_DIR.join("InstrumentSerif-Regular.ttf").to_s # the family has no bold
      }
    )
  end

  # Emoji (and their joiners/variation selectors) aren't in either font.
  def clean(value)
    value.to_s.gsub(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/, "").squeeze(" ").strip
  end

  # A recipe's ingredients (its own, then each component's) and its steps,
  # with components' sub-steps lettered underneath.
  def recipe_ingredients_and_steps(recipe)
    recipe.sections.each do |section|
      ingredients = section.own_ingredients
      next if ingredients.empty?

      text(clean(section.root? ? "Ingredients" : "For the #{section.recipe.title}"), size: 10, style: :bold)
      ingredients.each do |line|
        amount = line.quantity.positive? ? helpers.display_quantity_with_unit(line.quantity.round(2), line.unit) : nil
        text clean("•  #{[ amount.presence, line.ingredient&.ingredient, ('(optional)' if line.optional?) ].compact.join(' ')}"), size: 10
      end
      move_down 6
    end

    items = recipe.instruction_items
    return if items.empty?

    text "Steps", size: 10, style: :bold
    items.each_with_index do |item, n|
      if item.is_a?(Step)
        text clean("#{n + 1}.  #{item.content.to_plain_text.squish}"), size: 10, leading: 1.5
      else
        text clean("#{n + 1}.  Make the #{item.component_recipe.title}:"), size: 10
        item.component_recipe.steps.each_with_index do |step, s|
          indent(18) { text clean("#{(97 + s).chr}.  #{step.content.to_plain_text.squish}"), size: 10, leading: 1.5 }
        end
      end
      move_down 3
    end
  end

  def helpers
    @helpers ||= Class.new { include RecipeIngredientsHelper }.new
  end
end
