class Student < ApplicationRecord
  belongs_to :classroom, inverse_of: :students

  validates :classroom, presence: true
  validates :number,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :classroom_id }
  validates :name, presence: true
  validates :active, inclusion: { in: [true, false] }
end
