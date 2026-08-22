class RestructureHouseholdsForMemberships < ActiveRecord::Migration[8.1]
  def change
    # NOTE: if you already have household rows in production, split this into
    # add column (null: true) -> backfill owner_id -> change_column_null.
    add_reference :households, :owner, null: false, foreign_key: { to_table: :users }

    # user is optional: passive members (e.g. children) can exist without a login.
    add_reference :household_members, :user, foreign_key: true, index: false
    add_column :household_members, :role, :integer, null: false, default: 1 # limited

    # A user can hold at most one membership (and it also serves as the FK index).
    add_index :household_members, :user_id, unique: true
  end
end
