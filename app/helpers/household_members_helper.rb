module HouseholdMembersHelper
  # Whether the signed-in admin can reset this member's password: they need a
  # login, and it can't be the owner's or the admin's own (both are managed
  # from account settings).
  def password_manageable?(member)
    member.login? && !member.owner? && member.user_id != current_user.id &&
      member.household.admin?(current_user)
  end
end
