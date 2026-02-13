class Step < ApplicationRecord
  belongs_to :recipe
  has_rich_text :content

  acts_as_list scope: :recipe

  validates :content, presence: true

  before_validation :set_position, on: :create

  private

  def set_position
    self.position ||= recipe.steps.maximum(:position).to_i + 1 if recipe
  end
end