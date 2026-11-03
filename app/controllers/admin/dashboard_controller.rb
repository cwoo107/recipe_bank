# The admin landing page: how many households are where in billing, who's
# signed up lately, what's failed lately, and what admins have done.
class Admin::DashboardController < Admin::BaseController
  RECENT = 10

  # One row of "Needs attention".
  Problem = Data.define(:at, :label, :user, :error)

  def show
    @billing_counts = Household::Billing::BILLING_STATES.index_with { |state| Household.public_send(state).count }
    @household_count = Household.count

    people = User.where.not(email: User::DELETED_USERS_EMAIL)
    @user_count = people.count
    @signups = { "Last 7 days" => people.where(created_at: 7.days.ago..).count,
                 "Last 30 days" => people.where(created_at: 30.days.ago..).count }
    @recent_users = people.includes(:owned_household, household_membership: :household).order(created_at: :desc).limit(RECENT)

    @problems = recent_problems
    @claude_outage = claude_outage
    @actions = AdminAction.includes(:admin, :user, :household).order(created_at: :desc).limit(RECENT)
  end

  private

  # Failed recipe imports and receipt scans, and calendars that won't sync —
  # newest first, whoever they happened to.
  def recent_problems
    imports = RecipeImportJob.failed.includes(:user).order(updated_at: :desc).limit(RECENT).map do |import|
      Problem.new(at: import.updated_at, label: "Recipe import failed", user: import.user, error: import.error_detail.presence || import.error_message)
    end
    scans = ReceiptScan.failed.includes(:user).order(updated_at: :desc).limit(RECENT).map do |scan|
      Problem.new(at: scan.updated_at, label: "Receipt scan failed", user: scan.user, error: scan.error_detail.presence || scan.error_message)
    end
    calendars = CalendarSource.where.not(last_sync_error: [ nil, "" ]).includes(:user).order(updated_at: :desc).limit(RECENT).map do |source|
      Problem.new(at: source.last_sync_attempted_at || source.updated_at, label: "#{source.provider_label} sync failing",
                  user: source.user, error: source.last_sync_error)
    end

    (imports + scans + calendars).sort_by(&:at).reverse.first(RECENT)
  end

  # The latest Claude failure in the last day (out of credits, overloaded…),
  # if any — a banner, since it stops receipt uploads and file imports for
  # everyone. Only these failures have an error_detail (ClaudeUnavailableError).
  def claude_outage
    [ RecipeImportJob, ReceiptScan ].filter_map do |model|
      model.failed.where.not(error_detail: nil).where(updated_at: 1.day.ago..).order(updated_at: :desc).first
    end.max_by(&:updated_at)
  end
end
