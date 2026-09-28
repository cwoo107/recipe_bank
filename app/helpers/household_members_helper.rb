module HouseholdMembersHelper
  # A person's name as a small pill in their color — on chore and to-do cards.
  def person_pill(member, size: :sm)
    return if member.nil?

    padding = size == :xs ? "px-1.5 py-px text-[10px]" : "px-2 py-0.5 text-[11px]"
    content_tag :span, member.name,
                class: "inline-flex max-w-full items-center truncate rounded-full font-medium #{padding} #{member.color_classes[:pill]}"
  end

  def person_dot(member, size: "size-2.5")
    return if member.nil?

    content_tag :span, "", class: "inline-block shrink-0 rounded-full #{size} #{member.color_classes[:dot]}", aria: { hidden: true }
  end

  # Whether the signed-in admin can reset this member's password: they need a
  # login, and it can't be the owner's or the admin's own (both are managed
  # from account settings).
  def password_manageable?(member)
    member.login? && !member.owner? && member.user_id != current_user.id &&
      member.household.admin?(current_user)
  end
end
