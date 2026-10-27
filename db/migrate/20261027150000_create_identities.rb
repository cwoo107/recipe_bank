# Google / Apple sign-in: which provider account belongs to which user.
# A user can have several, alongside (or instead of) a password.
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
    end
    add_index :identities, %i[provider uid], unique: true
  end
end
