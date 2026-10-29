# "Also on your restock list?" — after the grocery list is generated, the
# user confirms which of the week's ingredients are things waiting on the
# restock list (RestockMatch). Every pair shown is saved either way
# (RestockItemIngredient), so it isn't asked about again.
class RestockMatchesController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_date, only: %i[new create]

  # Every pair the household has answered, linked and not, to change its mind
  # (from the restock checklist's "Manage linked ingredients").
  def index
    pairs = RestockItemIngredient.for_household(current_household).includes(:restock_item, :ingredient)
                                 .sort_by { |pair| [ pair.restock_item.name.downcase, pair.ingredient.ingredient.to_s.downcase ] }
    @linked, @unlinked = pairs.partition(&:linked?)
  end

  # Link or unlink one pair.
  def update
    pair = RestockItemIngredient.for_household(current_household).find(params[:id])
    pair.update!(linked: params[:linked] == "true")

    verb = pair.linked? ? "Linked" : "Unlinked"
    redirect_to restock_matches_path,
                notice: "#{verb} #{pair.ingredient.ingredient} and #{pair.restock_item.name}.", status: :see_other
  end

  def new
    @suggestions = RestockMatch.suggestions(current_household, @date)
    redirect_to grocery_lists_path(date: @date) if @suggestions.empty?
  end

  # Only pairs still on offer are saved — re-worked out here, so a posted key
  # can't name another household's item or an ingredient not on the list.
  def create
    confirmed = Array(params[:confirmed]).map(&:to_s).to_set
    suggestions = RestockMatch.suggestions(current_household, @date)

    RestockItemIngredient.transaction do
      suggestions.each do |suggestion|
        RestockItemIngredient.create!(restock_item: suggestion.restock_item, ingredient: suggestion.ingredient,
                                      linked: confirmed.include?(suggestion.key))
      end
    end

    linked = suggestions.count { |suggestion| confirmed.include?(suggestion.key) }
    notice = linked.zero? ? "Got it — none of those are on your restock list." :
                            "Linked #{helpers.pluralize(linked, 'grocery item')} to your restock list."
    redirect_to grocery_lists_path(date: @date), notice:, status: :see_other
  end

  private

  def set_date
    @date = (params[:date].present? ? Date.parse(params[:date]) : Time.zone.today).beginning_of_week
  rescue Date::Error
    @date = Time.zone.today.beginning_of_week
  end
end
