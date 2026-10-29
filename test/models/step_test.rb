require "test_helper"

class StepTest < ActiveSupport::TestCase
  setup do
    @recipe = recipes(:one)
  end

  test "attachments are stripped from a step's content, keeping its text" do
    step = @recipe.steps.create!(content: <<~HTML)
      <div>Whisk the eggs. <strong>Gently.</strong>
      <img src="https://evil.example/p.gif">
      <action-text-attachment url="https://evil.example/a.png" content-type="image/png"></action-text-attachment>
      <figure><img src="https://evil.example/b.png"></figure></div>
    HTML

    html = step.reload.content.body.to_html
    assert_no_match(/img|figure|action-text-attachment/, html)
    assert_includes html, "<strong>Gently.</strong>"
    assert_includes step.content.to_plain_text, "Whisk the eggs."
  end

  test "a step without attachments is saved as written" do
    step = @recipe.steps.create!(content: "<div>Bake for <em>20 minutes</em>.</div>")

    assert_includes step.reload.content.body.to_html, "Bake for <em>20 minutes</em>."
  end
end
