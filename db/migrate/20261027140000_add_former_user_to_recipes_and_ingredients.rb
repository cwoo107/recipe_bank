# Recipes and ingredients outlive a deleted account: they pass to the
# "Deleted Users" placeholder (User::AccountDeletion), and these record who
# they came from. No foreign key — that user is gone.
class AddFormerUserToRecipesAndIngredients < ActiveRecord::Migration[8.1]
  def change
    %i[recipes ingredients].each do |table|
      add_column table, :former_user_id, :integer
      add_column table, :former_user_email, :string
      add_index table, :former_user_id
    end
  end
end
