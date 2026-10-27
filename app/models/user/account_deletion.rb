# Deleting an account (Account settings → Danger zone). Everything of theirs
# goes except recipes and ingredients: those pass to the "Deleted Users"
# placeholder account, tagged with who they came from (former_user_id /
# former_user_email), so public recipes — and other households' meals,
# copies and favorites of them — keep working.
#
# An owner takes their whole household with them, every member's shared data
# included (the other members keep their logins and get a fresh household).
# A member leaving a household that carries on is removed just as an admin
# would remove them (Household#remove_member!): the recipes and lists they
# added stay with the household.
module User::AccountDeletion
  extend ActiveSupport::Concern

  # What the confirmation box must say.
  CONFIRMATION = "Delete Account"
  DELETED_USERS_EMAIL = "deleted-users@homemakershaven.invalid"

  class_methods do
    # The placeholder that keeps deleted accounts' recipes and ingredients.
    # It can't sign in, and its household is comped so billing leaves it be.
    def deleted_users
      find_by(email: DELETED_USERS_EMAIL) ||
        create!(email: DELETED_USERS_EMAIL, password: SecureRandom.base58(32), household_family_name: "Deleted Users").tap do |placeholder|
          placeholder.household.update_columns(comped_until: 100.years.from_now)
        end
    end
  end

  def deleted_users_placeholder?
    email == DELETED_USERS_EMAIL
  end

  # Devise: the placeholder never signs in.
  def active_for_authentication?
    super && !deleted_users_placeholder?
  end

  def delete_account!
    raise ArgumentError, "the Deleted Users placeholder can't be deleted" if deleted_users_placeholder?

    placeholder = User.deleted_users
    household = owned_household
    # First, so a refusal from Stripe stops the deletion rather than leaving
    # a subscription billing nobody.
    StripeBilling.cancel_subscription(household) if household

    transaction do
      AdminAction.where(admin_id: id).update_all(admin_id: placeholder.id)
      WeeklyPlanSection.where(updated_by_id: id).update_all(updated_by_id: nil) if household

      if household.nil? && household_membership
        hand_over_ingredients(created_ingredients, to: placeholder)
        member_household.remove_member!(household_membership)
      else
        recipes.update_all(user_id: placeholder.id, former_user_id: id, former_user_email: email, updated_at: Time.current)
        hand_over_ingredients(household.ingredients, to: placeholder, household: placeholder.household) if household
        hand_over_ingredients(created_ingredients, to: placeholder)
        household&.destroy!
        reload.destroy!
      end
    end
  end

  private

  # Credits each ingredient to whoever made it (or this account, when no one
  # did), and optionally moves it out of a household that's going away.
  def hand_over_ingredients(ingredients, to:, household: nil)
    ingredients.distinct.pluck(:created_by_id).each do |creator_id|
      creator = (User.find_by(id: creator_id) if creator_id) || self
      changes = { created_by_id: to.id, former_user_id: creator.id, former_user_email: creator.email, updated_at: Time.current }
      changes[:household_id] = household.id if household
      ingredients.where(created_by_id: creator_id).update_all(changes)
    end
  end
end
