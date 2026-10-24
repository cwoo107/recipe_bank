require "test_helper"

class ChoreTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
  end

  test "index lists the templates with an add button" do
    get chore_templates_url

    assert_response :success
    assert_select "#chore_template_admin h2", text: "Admin"
    assert_select "#chore_template_admin form[action=?] button", add_chore_template_path("admin"), text: /Add to chore chart/
  end

  test "a template the chart already has is marked as added" do
    ChoreTemplate.find("yard").add_to!(households(:one))
    get chore_templates_url

    assert_select "#chore_template_yard", text: /On your chart/
    assert_select "#chore_template_yard form", count: 0
  end

  test "a category with only some of the template's chores offers to add the rest" do
    get chore_templates_url

    # Standard Cleaning is a fixture category, with none of the template's chores.
    count = ChoreTemplate.find("standard_cleaning").chores.size
    assert_select "#chore_template_standard_cleaning button", text: /Add #{count} missing chores/
  end

  test "add copies the template onto the chart" do
    template = ChoreTemplate.find("home_maintenance")

    assert_difference -> { households(:one).chores.count } => template.chores.size do
      post add_chore_template_url(template)
    end
    assert_redirected_to weekly_chores_url(view: "table")
    assert_equal "Added #{template.chores.size} chores from \"Home Maintenance\" to your chore chart.", flash[:notice]
  end

  test "added weekly chores show on this week's board on their day" do
    post add_chore_template_url("standard_cleaning")
    get weekly_chores_url

    chore = households(:one).chores.find_by!(name: "Vacuum")
    instance = chore.weekly_chores.find_by!(week_start: Date.current.beginning_of_week)
    assert_equal "Wednesday", instance.scheduled_date.strftime("%A")
    assert_select "[id$=weekly_chore_#{instance.id}]"
  end

  test "add when everything's already there changes nothing" do
    template = ChoreTemplate.find("admin")
    template.add_to!(households(:one))

    assert_no_difference -> { households(:one).chores.count } do
      post add_chore_template_url(template)
    end
    assert_redirected_to chore_templates_url
  end

  test "unknown template is not found" do
    post add_chore_template_url("nope")
    assert_response :not_found
  end

  test "limited members can browse but not add" do
    sign_in users(:two) # bob, limited member of household :one
    get chore_templates_url
    assert_response :success
    assert_select "#chore_template_admin form", count: 0

    assert_no_difference -> { households(:one).chores.count } do
      post add_chore_template_url("admin")
    end
  end

  test "the chore chart links to the templates and prompts an empty chart" do
    get weekly_chores_url
    assert_select "a[href=?]", chore_templates_path, text: /Templates/
    assert_select "#chore_templates_prompt", count: 0

    households(:one).chores.destroy_all
    get weekly_chores_url
    assert_select "#chore_templates_prompt a[href=?]", chore_templates_path
  end
end
