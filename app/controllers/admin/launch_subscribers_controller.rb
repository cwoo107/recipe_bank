require "csv"

# The launch mailing list — who to email when sign-ups open. The CSV is the
# still-subscribed emails, for whatever sends the announcement.
class Admin::LaunchSubscribersController < Admin::BaseController
  def index
    @subscribers = LaunchSubscriber.newest_first

    respond_to do |format|
      format.html
      format.csv do
        csv = CSV.generate do |rows|
          rows << %w[email joined_on unsubscribe_url]
          @subscribers.subscribed.each do |subscriber|
            rows << [ subscriber.email, subscriber.created_at.to_date.iso8601, unsubscribe_launch_list_url(subscriber.unsubscribe_token) ]
          end
        end
        send_data csv, filename: "launch-list-#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
  end
end
