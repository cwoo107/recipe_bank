class AddFamilySizeAndOwnerMembers < ActiveRecord::Migration[8.1]
  # Lightweight stand-ins so this migration doesn't depend on app models.
  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  class MigrationMember < ActiveRecord::Base
    self.table_name = "household_members"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    # Number of people eating at home — the default servings for new meals.
    # Kept separately from the member list (not everyone gets listed), but
    # never below the number of listed members.
    add_column :households, :family_size, :integer, default: 1, null: false

    # The owner becomes a regular member row (tied to their login) so they can
    # be assigned meals, to-dos and chores like everyone else.
    MigrationHousehold.find_each do |household|
      unless MigrationMember.exists?(household_id: household.id, user_id: household.owner_id)
        email = MigrationUser.where(id: household.owner_id).pick(:email).to_s
        name  = email.split("@").first.presence&.titleize || "Me"
        MigrationMember.create!(household_id: household.id, user_id: household.owner_id, name: name, role: 0)
      end

      people = MigrationMember.where(household_id: household.id).count
      household.update_columns(family_size: [ people, 1 ].max)
    end
  end

  def down
    MigrationHousehold.find_each do |household|
      MigrationMember.where(household_id: household.id, user_id: household.owner_id).delete_all
    end
    remove_column :households, :family_size
  end
end
