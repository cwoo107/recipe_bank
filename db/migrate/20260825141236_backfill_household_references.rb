class BackfillHouseholdReferences < ActiveRecord::Migration[8.1]
  def up
    User.find_each do |user|
      household = user.household || user.create_owned_household!(family_name: default_family_name_for(user))

      Meal.where(user_id: user.id).update_all(household_id: household.id)
      Todo.where(user_id: user.id).update_all(household_id: household.id)
      GroceryList.where(user_id: user.id).update_all(household_id: household.id)
      CalendarSource.where(user_id: user.id).update_all(household_id: household.id)
      CalendarEvent.where(user_id: user.id).update_all(household_id: household.id)
    end

    renumber_positions
  end

  def down
    # Irreversible data backfill.
  end

  private

  def default_family_name_for(user)
    handle = user.email.to_s.split("@").first.presence || "New"
    "#{handle.titleize}'s Household"
  end

  # Two users' previously-independent acts_as_list `position` sequences can
  # now collide once Todo/CalendarSource share a household-wide scope
  # (see Part A's acts_as_list scope change) — renumber so ordering stays sane.
  def renumber_positions
    Household.find_each do |household|
      Todo::STATUSES.each do |status|
        household.todos.where(status: status).order(:position, :id).each_with_index do |todo, index|
          todo.update_column(:position, index + 1)
        end
      end

      household.calendar_sources.order(:position, :id).each_with_index do |source, index|
        source.update_column(:position, index + 1)
      end
    end
  end
end
