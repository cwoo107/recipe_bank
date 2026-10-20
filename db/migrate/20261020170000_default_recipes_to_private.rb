# New recipes start private (only the household sees them) rather than
# public. Only the column default changes — existing recipes keep whatever
# visibility they have.
class DefaultRecipesToPrivate < ActiveRecord::Migration[8.1]
  def change
    change_column_default :recipes, :visibility, from: "public", to: "private"
  end
end
