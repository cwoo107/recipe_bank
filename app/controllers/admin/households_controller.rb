# Find a household (by name or owner email, or billing state) and see where
# its account stands.
class Admin::HouseholdsController < Admin::BaseController
  PER_PAGE = 50

  def index
    @query = params[:q].to_s.strip
    @state = params[:state].presence_in(Household::Billing::BILLING_STATES)
    @page  = [ params[:page].to_i, 1 ].max

    households = Household.includes(:owner).order(created_at: :desc)
    households = households.public_send(@state) if @state
    if @query.present?
      term = "%#{Household.sanitize_sql_like(@query.downcase)}%"
      households = households.joins(:owner).where("LOWER(households.family_name) LIKE :term OR LOWER(users.email) LIKE :term", term:)
    end

    # One extra row tells us whether there's a next page.
    rows = households.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @next_page  = @page + 1 if rows.size > PER_PAGE
    @households = rows.first(PER_PAGE)
  end

  def show
    @household = Household.includes(:owner).find(params[:id])
    @members   = @household.people
    @recipe_count = Recipe.for_household(@household).count
    @actions   = AdminAction.where(household: @household).includes(:admin).order(created_at: :desc)
  end
end
