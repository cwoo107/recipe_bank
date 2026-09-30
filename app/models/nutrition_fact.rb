class NutritionFact < ApplicationRecord
  belongs_to :ingredient

  # Same spellings as recipe lines (UnitNormalizer), so a line's unit and its
  # ingredient's serving unit match when they mean the same thing — the
  # grocery list compares them directly.
  before_validation :normalize_serving_unit, if: :will_save_change_to_serving_unit?

  private

  def normalize_serving_unit
    self.serving_unit = UnitNormalizer.call(serving_unit).unit
  end
end
