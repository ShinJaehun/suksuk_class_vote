class Classroom < ApplicationRecord
  belongs_to :school
  belongs_to :teacher,
             class_name: "User",
             optional: true,
             inverse_of: :classroom

  validates :school, presence: true
  validates :name, presence: true, uniqueness: { scope: :school_id }
  validates :teacher_id, uniqueness: true, allow_nil: true

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
