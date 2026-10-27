# Everyone with a login: find someone (by email, their name in a household,
# or the household's name), see how they sign in and what's gone wrong for
# them lately, and view the app as them.
class Admin::UsersController < Admin::BaseController
  PER_PAGE = 50
  SIGN_IN_FILTERS = { "password" => "Password", "google_oauth2" => "Google", "apple" => "Apple" }.freeze

  def index
    @query   = params[:q].to_s.strip
    @sign_in = params[:sign_in].presence_in(SIGN_IN_FILTERS.keys)

    users = User.where.not(email: User::DELETED_USERS_EMAIL)
                .includes(:identities, :owned_household, household_membership: :household)
                .order(created_at: :desc)
    if @query.present?
      term = "%#{User.sanitize_sql_like(@query.downcase)}%"
      users = users.left_joins(household_membership: :household).where(
        "LOWER(users.email) LIKE :term OR LOWER(household_members.name) LIKE :term OR LOWER(households.family_name) LIKE :term", term:
      )
    end
    users = filter_by_sign_in(users) if @sign_in

    @pagy, @users = pagy(:offset, users, limit: PER_PAGE)
  end

  def show
    @user       = User.includes(:identities).find(params[:id])
    @household  = @user.household
    @membership = @user.household_membership
    @counts = {
      "Recipes"        => @user.recipes.count,
      "Favorites"      => @user.user_favorites.count,
      "Collections"    => @user.collections.count,
      "Recipe imports" => @user.recipe_import_jobs.count,
      "Receipt scans"  => @user.receipt_scans.count
    }
    @recipe_imports   = @user.recipe_import_jobs.order(created_at: :desc).limit(5)
    @receipt_scans    = @user.receipt_scans.order(created_at: :desc).limit(5)
    @calendar_sources = @user.calendar_sources.order(:position)
    @actions = AdminAction.where(user: @user).includes(:admin, :user).order(created_at: :desc)
  end

  private

  # "Password" means they've set one themselves — Google / Apple sign-ups
  # get a random one until they do (awaiting_first_password).
  def filter_by_sign_in(users)
    if @sign_in == "password"
      users.where(awaiting_first_password: false)
    else
      users.where(id: Identity.where(provider: @sign_in).select(:user_id))
    end
  end
end
