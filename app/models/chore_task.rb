# An optional step within a chore — "Clean toilet", "Mop floors" for
# "Clean the bathroom". Listed under the chore on Manage Chores and on its
# Chore Chart cards; a chore with none is just the chore.
class ChoreTask < ApplicationRecord
  belongs_to :chore

  acts_as_list scope: :chore_id

  validates :name, presence: true, length: { maximum: 100 }

  before_validation { self.name = name.to_s.strip }
end
