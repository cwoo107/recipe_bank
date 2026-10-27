# The launch mailing list: "Notify me" on the Coming soon page, and the
# unsubscribe link for the emails sent to it.
class LaunchSubscribersController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_active_subscription!
  layout "marketing"

  rate_limit to: 10, within: 10.minutes, only: :create,
             with: -> { redirect_to root_path(anchor: "launch-list"), alert: "Too many tries — please wait a few minutes." }

  def create
    subscriber = LaunchSubscriber.find_or_initialize_by(email: params.dig(:launch_subscriber, :email).to_s.strip.downcase)
    subscriber.unsubscribed_at = nil

    if subscriber.save
      redirect_to root_path(anchor: "launch-list"), notice: "You're on the list! We'll email you when we launch — and your first three months are on us."
    else
      redirect_to root_path(anchor: "launch-list"), alert: "Please enter a valid email address."
    end
  end

  def unsubscribe
    @subscriber = LaunchSubscriber.find_by!(unsubscribe_token: params[:token])
    @subscriber.unsubscribe!
  end
end
