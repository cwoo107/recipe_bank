class Step < ApplicationRecord
  belongs_to :recipe
  has_rich_text :content

  acts_as_list scope: :recipe

  # validates :content, presence: true

  before_validation :set_position, on: :create

  private

  def set_position
    return unless recipe

    self.position ||= recipe.steps.maximum(:position).to_i + 1
    # Lands at the end of the merged instruction list, past any component
    # recipes already sitting in it.
    self.instruction_position ||= recipe.next_instruction_position
  end
end