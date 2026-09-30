module AdminHelper
  BILLING_STATE_LABELS = {
    "comped"        => [ "Comped",        "bg-seafoam-100 text-seafoam-800 dark:bg-seafoam-900/30 dark:text-seafoam-300" ],
    "paying"        => [ "Paying",        "bg-sage-100 text-sage-800 dark:bg-white/10 dark:text-sage-100" ],
    "on_trial"      => [ "On trial",      "bg-honey-100 text-honey-800 dark:bg-honey-900/30 dark:text-honey-300" ],
    "trial_expired" => [ "Trial ended",   "bg-dusty-rose-100 text-dusty-rose-800 dark:bg-dusty-rose-900/30 dark:text-dusty-rose-300" ],
    "lapsed"        => [ "Lapsed",        "bg-gray-100 text-gray-700 dark:bg-white/10 dark:text-gray-300" ]
  }.freeze

  def billing_state_label(state) = BILLING_STATE_LABELS.fetch(state).first

  def billing_state_badge(household)
    label, classes = BILLING_STATE_LABELS.fetch(household.billing_state)
    tag.span(label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{classes}")
  end

  # Links into the Stripe Dashboard, in whichever mode the app's key is for.
  def stripe_dashboard_url(kind, id)
    mode = ENV["STRIPE_SECRET_KEY"].to_s.start_with?("sk_live") ? "" : "test/"
    "https://dashboard.stripe.com/#{mode}#{kind}/#{id}"
  end

  # "Extended trial from Oct 1 to Oct 15" and the like, for the audit list.
  def admin_action_summary(action)
    from, to = action.details.values_at("from", "to").map { |time| time && l(Time.zone.parse(time).to_date, format: :long) }

    case action.action
    when "extend_trial" then "Extended the trial from #{from} to #{to}"
    when "comp"         then to ? "Gave free access until #{to}" : "Ended free access"
    else action.action.humanize
    end
  end
end
