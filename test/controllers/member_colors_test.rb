require "test_helper"

class MemberColorsTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @household.household_members.each_with_index { |m, i| m.update_columns(color: Palette::NAMES[i]) } # olive, seafoam
    @bob = household_members(:one)
    sign_in users(:one)
  end

  test "new members get the first color nobody has yet" do
    kid = @household.invite_member(name: "Kid")
    assert_equal "honey", kid.color
  end

  test "a color picked in the form is kept, even one someone already has" do
    post household_members_url, params: { household_member: { name: "Twin", email: "", color: "olive" } }
    assert_equal "olive", HouseholdMember.find_by(name: "Twin").color
  end

  test "the member form has the same color picker as calendars, preselecting a free color" do
    get new_household_member_url
    assert_select "input[type=radio][name='household_member[color]']", count: Palette::NAMES.size
    assert_select "input[type=radio][name='household_member[color]'][value=honey][checked]"

    get edit_household_member_url(@bob)
    assert_select "input[type=radio][name='household_member[color]'][value=#{@bob.color}][checked]"
  end

  test "an admin can change a member's color" do
    patch household_member_url(@bob), params: { household_member: { name: "Bob", color: "dusty-rose" } }
    assert_equal "dusty-rose", @bob.reload.color
  end

  test "only palette colors are allowed" do
    assert_not @bob.update(color: "neon")
  end

  test "chore and to-do cards show the person as a pill in their color, with no colored border" do
    week = Date.current.beginning_of_week
    chore = @household.weekly_chores.create!(chore: chores(:one), week_start: week, scheduled_date: week, assignee: @bob)
    todo  = @household.todos.create!(title: "Fix fence", priority: :medium, status: "todo", user: users(:one), assignee: @bob)
    pill  = Palette.person_classes(@bob.color)[:pill].split.first

    get weekly_chores_url
    assert_select "#weekly_chore_#{chore.id}[class*=border-l-4]", count: 0
    assert_select "#weekly_chore_#{chore.id} span.#{pill}", text: "Bob"

    get todos_url
    assert_select "#todo_#{todo.id} span.#{pill}", text: "Bob"
    assert_select "#todo_#{todo.id}[class*=border-l-4]", count: 0
  end

  test "the calendar form still uses the shared picker" do
    get new_calendar_source_url
    assert_select "input[type=radio][name='calendar_source[color]']", count: CalendarSource::COLORS.size
  end

  test "the printed chore chart and to-dos use each person's color" do
    week = Date.current.beginning_of_week
    @household.weekly_chores.create!(chore: chores(:one), week_start: week, scheduled_date: week, assignee: @bob)
    @household.todos.create!(title: "Paint", priority: :medium, status: "in_progress", user: users(:one), assignee: @bob)

    %w[chores todos].each do |section|
      pdf = WeekPlanPdf.new(household: @household, week_start: week, sections: [ section ]).render
      tint = Palette.print_colors(@bob.color)[:bg]
      r, g, b = tint.scan(/../).map { |c| Regexp.escape(format("%.5f", c.to_i(16) / 255.0)[0, 6]) }
      assert_match(/#{r}\d* #{g}\d* #{b}\d* scn/, pdf, "#{section} page uses Bob's color")
    end
  end
end
