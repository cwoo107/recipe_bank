class Household < ApplicationRecord
  include Household::Billing

  belongs_to :owner, class_name: "User", inverse_of: :owned_household

  has_many :household_members, dependent: :destroy
  has_many :members, through: :household_members, source: :user

  has_many :meals,            dependent: :destroy
  has_many :recurring_meals,  dependent: :destroy
  has_many :todos,            dependent: :destroy
  has_many :restock_items,    dependent: :destroy
  has_many :restock_categories, dependent: :destroy
  has_many :chore_categories, dependent: :destroy
  has_many :chores,           dependent: :destroy
  has_many :weekly_chores,    dependent: :destroy
  has_many :grocery_lists,    dependent: :destroy
  has_many :calendar_sources, dependent: :destroy
  has_many :calendar_events,  dependent: :destroy
  has_many :weekly_plans,     dependent: :destroy
  # Left behind as unowned catalog entries rather than destroyed, so recipes
  # still pointing at them keep their lines.
  has_many :ingredients,      dependent: :nullify

  validates :family_name, presence: true
  validates :minutes_per_day, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :week_start_day, inclusion: { in: 0..6 }
  validates :family_size, numericality: { only_integer: true, greater_than: 0 }
  validate :time_zone_is_known
  validate :family_size_covers_listed_members, on: :update
  validate :plans_at_least_one_section

  after_create :create_owner_member
  after_create :seed_default_restock_categories
  after_create :seed_default_chore_categories
  after_update :realign_weeks, if: :saved_change_to_week_start_day?

  def self.default_family_name_for(user)
    handle = user.email.to_s.split("@").first.presence || "New"
    "#{handle.titleize}'s Household"
  end

  # The household's zone for pages and calendar syncing; falls back to the
  # app default (UTC) until one's set.
  def zone
    ActiveSupport::TimeZone[time_zone.to_s] || Time.zone_default
  end

  # For the settings picker: every zone Rails knows, by UTC offset, as IANA
  # names (what browsers report), plus the current one if it isn't listed.
  def self.time_zone_options(current = nil)
    options = ActiveSupport::TimeZone.all.map { |z| [ "(GMT#{z.formatted_offset}) #{z.name}", z.tzinfo.name ] }
                                     .uniq(&:last)
    if current.present? && options.none? { |_, id| id == current }
      options.unshift([ current.tr("_", " "), current ])
    end
    options
  end

  # Options for the week start picker, in calendar order (Sunday first).
  def self.week_start_day_options
    Date::DAYNAMES.each_with_index.map { |name, wday| [ name, wday ] }
  end

  # The week start as the symbol Date#beginning_of_week expects (:monday etc.).
  # ApplicationController sets Date.beginning_of_week to this for every
  # request, so plain `date.beginning_of_week` calls follow the household's
  # setting without threading it through.
  def week_start_symbol
    Date::DAYNAMES.fetch(week_start_day).downcase.to_sym
  end

  def week_start_day_name
    Date::DAYNAMES.fetch(week_start_day)
  end

  # Weekday numbers (0 = Sunday) in the order this household's weeks run —
  # for day-of-week headers and pickers.
  def ordered_wdays
    (0..6).map { |i| (week_start_day + i) % 7 }
  end

  # "The Anderson household" — or the name as-is when it already says
  # household (the signup default is "Alice's Household").
  def display_name
    family_name.to_s.match?(/household\z/i) ? family_name : "the #{family_name} household"
  end

  # The owner's own member row — every household has one (created alongside
  # the household), so the owner can be assigned meals, to-dos and chores.
  def owner_member
    household_members.find_by(user_id: owner_id)
  end

  # Everyone listed in the household, owner first.
  def people
    household_members.includes(:user).order(Arel.sql("CASE WHEN household_members.user_id = #{owner_id.to_i} THEN 0 ELSE 1 END"), :name)
  end

  # The first palette color no one in the household has yet (wrapping around
  # once all six are used) — new members' default.
  def next_member_color
    taken = household_members.pluck(:color)
    Palette::NAMES.find { |name| taken.exclude?(name) } || Palette::NAMES[taken.size % Palette::NAMES.size]
  end

  # Assignment controls (who's eating, who's doing it) only appear once
  # there's someone besides the owner to choose from — households that never
  # list anyone never see them.
  def assignable?
    household_members.size > 1
  end

  # People with their own assigned meal at a breakfast/lunch/dinner — they
  # aren't eating that slot's shared meals (see MealWeekStats).
  def assigned_member_ids_in_slot(date, meal_name, except: nil)
    return [] unless date && Meal::CALENDAR_TYPES.include?(meal_name.to_s.downcase)

    MealAssignment.joins(:meal)
                  .where(meals: { household_id: id, date: date })
                  .where("LOWER(meals.meal_name) = ?", meal_name.to_s.downcase)
                  .where.not(meal_id: except&.id)
                  .distinct.pluck(:household_member_id)
  end

  # Default servings for a shared meal in a slot: the family, minus anyone
  # already having their own assigned meal then.
  def default_servings_for(date:, meal_name:, except: nil)
    [ family_size - assigned_member_ids_in_slot(date, meal_name, except:).size, 1 ].max
  end

  # Family size never drops below the number of listed people — adding a
  # member beyond the current size bumps it (see HouseholdMember).
  def grow_family_size_to_fit_members!
    listed = household_members.count
    update_column(:family_size, listed) if listed > family_size
  end

  # ── Weekly planner steps ──────────────────────────────────────────────
  # A household can leave planning areas it never uses (say, to-dos) out of
  # "Plan your week". They stay in the navigation and on the dashboard; they
  # just aren't steps to walk through, and start unticked on the print page.
  # Stored as the excluded keys (excluded_planner_sections), so an area added
  # later is included by default.

  # The planner's steps, in Dashboard order.
  def planner_section_keys
    Dashboard.section_keys - Array(excluded_planner_sections)
  end

  def plans_section?(key) = planner_section_keys.include?(key.to_s)

  # The settings form posts the keys to include; everything else is excluded.
  def planner_sections=(included_keys)
    included = Array(included_keys).map(&:to_s)
    self.excluded_planner_sections = Dashboard.section_keys - included
  end

  # Print pages that follow a planner step when it's left out — the recipes
  # page belongs to the meal plan.
  PRINT_SECTIONS_FOR_PLANNER = { "meals" => %w[meals recipes] }.freeze

  # What the print page ticks by default: every page, minus those belonging
  # to steps left out of the planner.
  def default_print_sections
    left_out = Array(excluded_planner_sections).flat_map { |key| PRINT_SECTIONS_FOR_PLANNER.fetch(key, [ key ]) }
    WeekPlanPdf::SECTIONS.keys - left_out
  end

  def owner?(user)
    owner_id == user&.id
  end

  # Owner + admin sub-users have full control.
  def admin?(user)
    owner?(user) || household_members.admin.exists?(user_id: user&.id)
  end

  def member?(user)
    owner?(user) || household_members.exists?(user_id: user&.id)
  end

  # Everyone who can log in and see this household's data.
  def users
    User.where(id: [owner_id] + household_members.with_login.pluck(:user_id))
  end

  # Creates a sub-user with their own Devise login and a membership row, then
  # emails them a set-your-password link. Without an email, adds a member with
  # no login instead (a child, or anyone who won't use the app). Returns the
  # (possibly unpersisted, error-laden) HouseholdMember either way, so
  # controllers can re-render forms.
  def invite_member(name: nil, email: nil, role: :limited, color: nil)
    member = household_members.new(name:, role:)
    member.assign_attributes(color:, color_chosen: true) if color.present?

    if email.blank?
      member.role = :limited
      member.save
      return member
    end

    transaction do
      user = build_member_login(email)
      user.save!

      member.user = user
      member.save!

      user.send_household_invitation(household: self)
    end

    member
  rescue ActiveRecord::RecordInvalid => e
    member.errors.merge!(e.record.errors) unless e.record.equal?(member)
    member
  end

  # Turns an existing no-login member into one who can sign in — same member
  # row, so their meal, chore and to-do assignments carry over — and emails
  # them a set-your-password link. Returns false (with errors on the member,
  # e.g. an email already in use) if it couldn't.
  def give_login(member, email:)
    user = build_member_login(email)

    transaction do
      user.save!
      member.update!(user: user)
    end
    user.send_household_invitation(household: self)
    true
  rescue ActiveRecord::RecordInvalid => e
    member.errors.merge!(e.record.errors) unless e.record.equal?(member)
    member.restore_attributes([ :user_id ])
    false
  end

  # Records a member's login creates that belong to the household rather than
  # the person — these pass to the owner when the member is removed, instead
  # of being deleted with the login (or blocking its deletion).
  HANDED_OFF_ON_REMOVAL = %w[Recipe Tag Collection Meal RecurringMeal Todo GroceryList
                             RestockItem CalendarSource CalendarEvent].freeze

  # Removes a member, and their login if they have one. Everything their login
  # created for the household is handed to the owner first; only personal
  # bits (favorites, import history) go with the login. All or nothing.
  def remove_member!(member)
    raise ArgumentError, "the owner can't be removed" if member.owner?

    transaction do
      user = member.user
      member.destroy!
      next unless user

      HANDED_OFF_ON_REMOVAL.each { |name| name.constantize.where(user_id: user.id).update_all(user_id: owner_id) }
      WeeklyPlanSection.where(updated_by_id: user.id).update_all(updated_by_id: owner_id)
      user.reload.destroy!
    end
  end

  private

  # A sub-user login with a throwaway password — they set their own from the
  # emailed reset link.
  def build_member_login(email)
    User.new(email:, password: SecureRandom.base58(24), skip_household_provisioning: true,
             awaiting_first_password: true).tap do |user|
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    end
  end

  def time_zone_is_known
    return if time_zone.blank? || ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, "isn't a time zone we recognize")
  end

  def plans_at_least_one_section
    return if planner_section_keys.any?

    errors.add(:base, "Keep at least one step in the weekly planner")
  end

  def family_size_covers_listed_members
    listed = household_members.count
    return if family_size.to_i >= listed

    errors.add(:family_size, "can't be less than the #{listed} people listed in your household")
  end

  # A login can only belong to one member row, so an owner who's already a
  # member somewhere keeps that row.
  def create_owner_member
    return if HouseholdMember.exists?(user_id: owner_id)

    household_members.create!(user: owner, name: owner.email.to_s.split("@").first.presence&.titleize || "Me", role: :admin)
  end

  def realign_weeks
    old_day, new_day = saved_change_to_week_start_day
    Household::WeekRealignment.new(self, from: old_day, to: new_day).call
  end

  def seed_default_restock_categories
    RestockCategory::DEFAULT_NAMES.each_with_index do |name, index|
      restock_categories.create!(name: name, position: index + 1)
    end
  end

  def seed_default_chore_categories
    ChoreCategory::DEFAULT_NAMES.each_with_index do |name, index|
      chore_categories.create!(name: name, position: index + 1)
    end
  end
end
