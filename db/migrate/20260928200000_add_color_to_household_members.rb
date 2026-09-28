class AddColorToHouseholdMembers < ActiveRecord::Migration[8.1]
  class MigrationMember < ActiveRecord::Base
    self.table_name = "household_members"
  end

  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  # Same palette as calendars (CalendarSource::COLORS).
  PALETTE = %w[olive seafoam honey mist mauve dusty-rose].freeze

  def up
    # Each person's color on the chore chart and to-dos.
    add_column :household_members, :color, :string, default: "olive", null: false

    # Give everyone already listed a different color, owner first.
    MigrationHousehold.find_each do |household|
      members = MigrationMember.where(household_id: household.id)
                               .order(Arel.sql("CASE WHEN user_id = #{household.owner_id.to_i} THEN 0 ELSE 1 END"), :id)
      members.each_with_index { |member, i| member.update_columns(color: PALETTE[i % PALETTE.size]) }
    end
  end

  def down
    remove_column :household_members, :color
  end
end
