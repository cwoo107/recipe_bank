# A single recipe as a PDF (RecipePdf) — the Print button on a recipe's
# page. Anything the household can open, it can print; streamed straight
# back, never saved.
class RecipePrintsController < ApplicationController
  def show
    recipe = Recipe.browsable_by_household(current_household).find(params.expect(:recipe_id))
    pdf = RecipePdf.new(recipe:)
    send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
  end
end
