# A household's own category labels for to-dos — "Yard", "Paperwork". Kept
# apart from Tag, which labels recipes. Colors come from the Palette names so
# the pills match people's pills elsewhere on the board.
class TodoTag < ApplicationRecord
  belongs_to :household

  has_many :todo_taggings, dependent: :destroy
  has_many :todos, through: :todo_taggings

  validates :name,  presence: true, uniqueness: { scope: :household_id, case_sensitive: false }
  validates :color, inclusion: { in: Palette::NAMES }

  before_validation { self.name = name.to_s.strip }
  before_validation :pick_color, on: :create

  scope :ordered, -> { order(:name) }

  def pill_classes = Palette.person_classes(color)[:pill]
  def dot_classes  = Palette.person_classes(color)[:dot]
  # For the tag picker's dots, which are drawn in JavaScript.
  def hex_color    = "##{Palette.print_colors(color)[:dot]}"

  private

  # Cycle through the palette so each new tag looks different from the last.
  def pick_color
    self.color = Palette::NAMES[household.todo_tags.count % Palette::NAMES.size] if color.blank? && household
  end
end
