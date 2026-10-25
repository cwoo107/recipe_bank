class TodoTagging < ApplicationRecord
  belongs_to :todo
  belongs_to :todo_tag

  validates :todo_tag_id, uniqueness: { scope: :todo_id }
end
