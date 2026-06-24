class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  # Pundit-style ownership check without the gem overhead.
  # Raises a 403 if the given record doesn't belong to current_user.
  def require_ownership!(record, owner_method: :user)
    owner = record.public_send(owner_method)
    unless owner == current_user
      redirect_to root_path, alert: "You don't have permission to do that."
    end
  end

  # For ingredients where the column is created_by_id, not user_id
  def require_ingredient_ownership!(ingredient)
    unless ingredient.editable_by?(current_user)
      redirect_to ingredients_path, alert: "You can only edit ingredients you created."
    end
  end
end