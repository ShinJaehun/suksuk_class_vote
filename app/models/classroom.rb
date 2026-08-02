class Classroom < ApplicationRecord
  belongs_to :school
  belongs_to :teacher,
             class_name: "User",
             optional: true,
             inverse_of: :classrooms
  has_many :students,
           dependent: :restrict_with_error,
           inverse_of: :classroom

  validates :school, presence: true
  validates :name, presence: true
  validates :school_year,
            :grade,
            :class_number,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :class_number,
            uniqueness: { scope: %i[school_id school_year grade] }
  validates :active, inclusion: { in: [true, false] }
  validates :teacher_id,
            uniqueness: { conditions: -> { where(active: true) } },
            allow_nil: true,
            if: :active?

  validate :teacher_must_be_teacher
  validate :teacher_must_belong_to_school
  validate :school_cannot_change, on: :update

  private

  def teacher_must_be_teacher
    return if teacher.blank? || teacher.teacher?

    errors.add(:teacher, "must be a teacher")
  end

  def teacher_must_belong_to_school
    return if teacher.blank? || school.blank?
    return unless teacher.teacher?
    return if teacher.school == school

    errors.add(:teacher, "must belong to the classroom school")
  end

  def school_cannot_change
    return unless will_save_change_to_school_id?

    errors.add(:school, "cannot be changed")
  end
end
