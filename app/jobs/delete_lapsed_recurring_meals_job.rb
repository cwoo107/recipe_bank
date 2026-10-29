# Daily (config/schedule.yml): deletes recurring meals whose end date has
# passed (RecurringMeal.delete_lapsed!), so the Manage recurring meals list
# doesn't fill up with finished ones. The meals they scheduled stay on the
# calendar.
class DeleteLapsedRecurringMealsJob < ApplicationJob
  queue_as :default

  def perform
    removed = RecurringMeal.delete_lapsed!
    Rails.logger.info "DeleteLapsedRecurringMealsJob: removed #{removed} lapsed recurring meal(s)" if removed.positive?
  end
end
