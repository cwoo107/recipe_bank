class Step < ApplicationRecord
  belongs_to :recipe
  has_rich_text :content

  acts_as_list scope: :recipe

  # validates :content, presence: true

  before_validation :set_position, on: :create
  before_save :remove_attachments

  private

  # Steps are text only. Attachments (uploaded files, or images linked from
  # elsewhere) are dropped however they arrive — the editor no longer offers
  # them, but a crafted request or an import could still send one.
  def remove_attachments
    body = content&.body
    return if body.blank?

    fragment = Nokogiri::HTML5.fragment(body.to_html)
    attachments = fragment.css("action-text-attachment, figure, img")
    return if attachments.empty?

    attachments.each(&:remove)
    content.body = fragment.to_html
  end

  def set_position
    return unless recipe

    self.position ||= recipe.steps.maximum(:position).to_i + 1
    # Lands at the end of the merged instruction list, past any component
    # recipes already sitting in it.
    self.instruction_position ||= recipe.next_instruction_position
  end
end