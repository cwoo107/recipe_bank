# Featured is a yes/no flag — no "unknown" — so existing rows backfill to false.
class DefaultFeaturedToFalseOnRecipes < ActiveRecord::Migration[8.1]
  def change
    change_column_default :recipes, :featured, from: nil, to: false
    change_column_null :recipes, :featured, false, false
  end
end
