require "test_helper"

class ChoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get chores_url
    assert_response :success
  end

  test "should create chore" do
    assert_difference("Chore.count") do
      post chores_url, params: { chore: { name: "Vacuum", frequency: "weekly" } }
    end

    assert_equal households(:one), Chore.last.household
  end

  test "should update chore" do
    patch chore_url(@chore), params: { chore: { name: "Updated" } }
    assert_redirected_to chores_url
    assert_equal "Updated", @chore.reload.name
  end

  test "update redirects to return_to when it's a local path (e.g. back to the board)" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "/weekly_chores?date=2026-08-24" }
    assert_redirected_to "/weekly_chores?date=2026-08-24"
  end

  test "update ignores an external return_to to avoid an open redirect" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "https://evil.example.com/phish" }
    assert_redirected_to chores_url
  end

  test "should destroy chore" do
    assert_difference("Chore.count", -1) do
      delete chore_url(@chore)
    end
  end

  test "a user in a different household cannot edit the chore" do
    sign_in users(:three) # carol, household :two

    patch chore_url(@chore), params: { chore: { name: "Should not work" } }
    assert_response :not_found
  end

  test "inline update refreshes the row via turbo stream" do
    patch chore_url(@chore), params: { inline: 1, chore: { chore_category_id: chore_categories(:standard_cleaning_one).id } }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal chore_categories(:standard_cleaning_one), @chore.reload.chore_category
  end

  test "update ignores another household's category" do
    patch chore_url(@chore), params: { chore: { chore_category_id: chore_categories(:chores_two).id } }

    assert_equal chore_categories(:chores_one), @chore.reload.chore_category
  end

  test "picking a day for a weekly chore reschedules it from this week forward" do
    week_start = Date.current.beginning_of_week
    instance = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    patch chore_url(@chore), params: { inline: 1, chore: { default_weekday: (week_start + 4).wday } }

    assert_equal (week_start + 4).wday, @chore.reload.default_weekday
    assert_equal week_start + 4, instance.reload.scheduled_date
  end

  test "index renders the inline editor and category manager" do
    get chores_url
    assert_select "form#chore_inline_form_#{@chore.id}[action=?]", chore_path(@chore)
    assert_select "input[value=?]", "Standard Cleaning"
  end

  test "the desktop table shows plain text that swaps to fields tied to the row's form" do
    get chores_url

    assert_select "tr#chore_#{@chore.id}" do
      assert_select "[data-inline-cell-target=text]", text: "Take out trash"
      assert_select "[data-inline-cell-target=text]", text: "Chores"
      assert_select "[data-inline-cell-target=text]", text: "Weekly"
      assert_select "input[name=?][form=?]", "chore[name]", "chore_inline_form_#{@chore.id}"
      assert_select "select[name=?][form=?]", "chore[chore_category_id]", "chore_inline_form_#{@chore.id}"
      assert_select "select[name=?][form=?]", "chore[frequency]", "chore_inline_form_#{@chore.id}"
      assert_select "select[name=?][form=?]", "chore[default_weekday]", "chore_inline_form_#{@chore.id}"
    end
  end

  test "inline update refreshes the computed columns" do
    patch chore_url(@chore), params: { inline: 1, from: "desktop", chore: { name: "Trash night" } }, as: :turbo_stream

    assert_match(/chore_next_due_#{@chore.id}/, response.body)
    assert_equal "Trash night", @chore.reload.name
  end

  test "a limited member sees the table without editable cells" do
    sign_in users(:two) # bob, a limited member of household :one
    get chores_url

    assert_select "tr#chore_#{@chore.id}" do
      assert_select "[data-controller=inline-cell]", 0
      assert_select "input[name=?]", "chore[name]", 0
    end
  end

  test "the table has no Mark done or Undo buttons" do
    @chore.update!(last_completed_at: 1.day.ago)
    get chores_url

    assert_select "button", text: /Mark done/, count: 0
    assert_select "button", text: /Undo last/, count: 0
  end
end
