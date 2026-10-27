# "View as" for app admins (Admin::ImpersonationsController): the admin
# stays signed in as themselves (true_user) while current_user — and with
# it current_household, permissions and everything else — becomes the
# person they're helping, so they see exactly what that person sees.
#
# It's read-only. Anything but a GET is refused, and GETs run in a
# transaction that's always rolled back, since some pages fill things in as
# they load (recurring meals, the week's plan). Jobs are only enqueued from
# non-GET actions, so nothing leaves the app either — except the billing
# pages' calls to Stripe, which are refused outright.
module Impersonation
  extend ActiveSupport::Concern

  TIMEOUT = 1.hour

  # GETs that reach outside the database, refused like writes.
  BLOCKED_CONTROLLERS = %w[billings].freeze

  included do
    prepend_around_action :read_only_while_impersonating
    helper_method :true_user, :impersonated_user, :impersonating?, :impersonation_ends_at
  end

  def current_user
    impersonated_user || true_user
  end

  private

  # Devise's user — the one actually signed in, whoever they're viewing as.
  def true_user
    warden.authenticate(scope: :user)
  end

  def impersonating?
    impersonated_user.present?
  end

  def impersonation_ends_at
    Time.zone.at(session[:impersonation]["started_at"]) + TIMEOUT if session[:impersonation]
  end

  def impersonated_user
    return @impersonated_user if defined?(@impersonated_user)

    data = session[:impersonation]
    @impersonated_user =
      if data && true_user&.app_admin? && impersonation_ends_at.future?
        User.find_by(id: data["user_id"])
      end
  end

  def start_impersonating(user, note: nil)
    stop_impersonating if session[:impersonation]

    session[:impersonation] = { "user_id" => user.id, "started_at" => Time.current.to_i }
    remove_instance_variable(:@impersonated_user) if defined?(@impersonated_user)
    AdminAction.record!(admin: true_user, household: user.household, user:, action: "impersonation_started", note:)
  end

  # Returns who they were viewing as, if anyone.
  def stop_impersonating(reason: nil)
    data = session.delete(:impersonation)
    remove_instance_variable(:@impersonated_user) if defined?(@impersonated_user)
    user = User.find_by(id: data["user_id"]) if data

    if user && true_user&.app_admin?
      AdminAction.record!(admin: true_user, household: user.household, user:, action: "impersonation_ended",
                          details: { reason: }.compact)
    end
    user
  end

  def read_only_while_impersonating
    stop_impersonating(reason: "timed_out") if session[:impersonation] && !impersonating?
    return yield unless impersonating?

    # Signing out ends it too (and signs the admin out).
    if devise_controller? && controller_name == "sessions" && action_name == "destroy"
      stop_impersonating(reason: "signed_out")
      return yield
    end

    if (request.get? || request.head?) && !controller_name.in?(BLOCKED_CONTROLLERS)
      # requires_new: a savepoint, so it rolls back even inside another
      # transaction (e.g. a test's).
      ActiveRecord::Base.transaction(requires_new: true) do
        yield
        raise ActiveRecord::Rollback
      end
    else
      refuse_while_impersonating
    end
  end

  def refuse_while_impersonating
    message = "Read-only while viewing as #{current_user.email} — nothing was changed."

    if request.format.html? || request.format.turbo_stream?
      redirect_back_or_to dashboard_path, alert: message, status: :see_other
    else
      head :forbidden
    end
  end
end
