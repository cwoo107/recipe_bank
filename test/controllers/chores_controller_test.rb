require "test_helper"

class ChoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "the old Manage Chores page redirects to the Chore Chart's Table View" do
    get chores_url
    assert_redirected_to weekly_chores_url(view: "table")
  end

  test "should create chore" do
    assert_difference("Chore.count") do
      post chores_url, params: { chore: { name: "Vacuum", frequency: "weekly" } }
    end

    assert_equal households(:one), Chore.last.household
  end

  test "should update chore" do
    patch chore_url(@chore), params: { chore: { name: "Updated" } }
    assert_redirected_to weekly_chores_url(view: "table")
    assert_equal "Updated", @chore.reload.name
  end

  test "update redirects to return_to when it's a local path (e.g. back to the board)" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "/weekly_chores?date=2026-08-24" }
    assert_redirected_to "/weekly_chores?date=2026-08-24"
  end

  test "update ignores an external return_to to avoid an open redirect" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "https://evil.example.com/phish" }
    assert_redirected_to weekly_chores_url(view: "table")
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
    get weekly_chores_url(view: "table")
    assert_select "form#chore_inline_form_#{@chore.id}[action=?]", chore_path(@chore)
    assert_select "input[value=?]", "Standard Cleaning"
  end

  test "the desktop table shows plain text that swaps to fields tied to the row's form" do
    get weekly_chores_url(view: "table")

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
    get weekly_chores_url(view: "table")

    assert_select "tr#chore_#{@chore.id}" do
      assert_select "[data-controller=inline-cell]", 0
      assert_select "input[name=?]", "chore[name]", 0
    end
  end

  test "the table has no Mark done or Undo buttons" do
    @chore.update!(last_completed_at: 1.day.ago)
    get weekly_chores_url(view: "table")

    assert_select "button", text: /Mark done/, count: 0
    assert_select "button", text: /Undo last/, count: 0
  end

  test "the table's Last done cell edits the date" do
    get weekly_chores_url(view: "table")

    assert_select "#chore_last_done_#{@chore.id} input[type=date][name=?][form=?]", "chore[last_completed_at]", "chore_inline_form_#{@chore.id}"
  end

  test "editing Last done moves Next due along with it" do
    @chore.update!(frequency: "monthly")

    patch chore_url(@chore), params: { inline: 1, from: "desktop", chore: { last_completed_at: "2026-09-01" } }, as: :turbo_stream

    assert_response :success
    assert_equal Date.new(2026, 9, 1), @chore.reload.last_completed_at.to_date
    assert_equal Date.new(2026, 10, 1), @chore.next_due_date
    assert_match "Tue, Sep 1", response.body
  end

  test "clearing Last done sets it back to never" do
    @chore.update!(last_completed_at: 3.days.ago)

    patch chore_url(@chore), params: { inline: 1, from: "desktop", chore: { last_completed_at: "" } }, as: :turbo_stream

    assert_nil @chore.reload.last_completed_at
  end

  test "Last done can't be in the future" do
    @chore.update!(last_completed_at: 3.days.ago)

    patch chore_url(@chore), params: { inline: 1, from: "desktop", chore: { last_completed_at: (Date.current + 2).iso8601 } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Last done can&#39;t be in the future", response.body
    assert_equal 3.days.ago.to_date, @chore.reload.last_completed_at.to_date
  end

  test "the table's column headings sort by that column, and the current one flips direction" do
    get weekly_chores_url(view: "table")

    assert_select "th[aria-sort=ascending] a[href=?]", weekly_chores_path(view: "table", sort: "next_due", direction: "desc"), text: /Next due/
    assert_select "th[aria-sort=none] a[href=?]", weekly_chores_path(view: "table", sort: "name", direction: "asc"), text: /Chore/

    get weekly_chores_url(view: "table", sort: "name", direction: "desc")
    assert_select "th[aria-sort=descending]", text: /Chore/
    assert_select "th[aria-sort=none]", text: /Next due/
  end

  test "the table starts sorted by next due: overdue first, furthest out last" do
    households(:one).chores.update_all(last_completed_at: 1.day.ago)
    overdue = households(:one).chores.create!(name: "Overdue job", frequency: "monthly", last_completed_at: 2.months.ago)
    far_out = households(:one).chores.create!(name: "Far-out job", frequency: "annually", last_completed_at: 1.day.ago)

    get weekly_chores_url(view: "table")

    rows = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal "chore_#{overdue.id}", rows.first
    assert_equal "chore_#{far_out.id}", rows.last
  end

  test "sorting reorders the table's rows" do
    households(:one).chores.create!(name: "Aardvark wash", frequency: "monthly")
    households(:one).chores.create!(name: "Zebra brushing", frequency: "monthly")

    get weekly_chores_url(view: "table", sort: "name", direction: "desc")
    rows = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal "chore_#{Chore.find_by!(name: 'Zebra brushing').id}", rows.first
    assert_equal "chore_#{Chore.find_by!(name: 'Aardvark wash').id}", rows.last
  end

  test "the Filter panel narrows the table and keeps the sort" do
    households(:one).chores.create!(name: "Monthly job", frequency: "monthly")

    get weekly_chores_url(view: "table", frequency: "monthly", sort: "name", direction: "desc")

    rows = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal [ "chore_#{Chore.find_by!(name: 'Monthly job').id}" ], rows
    assert_select "select[name=frequency] option[selected][value=monthly]"
    assert_select "form input[type=hidden][name=sort][value=name]"
    assert_select "button", text: /Filter\s*1/
    # Sorting another column keeps the filter.
    assert_select "th a[href*='frequency=monthly'][href*='sort=next_due']"
  end

  test "filters with no matches say so, with a way back" do
    get weekly_chores_url(view: "table", frequency: "annually")

    assert_select "p", text: "No chores match these filters."
    assert_select "a", text: "Clear filters"
  end
end
