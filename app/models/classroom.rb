class Classroom < ApplicationRecord
  belongs_to :school
  belongs_to :teacher,
             class_name: "User",
             optional: true,
             inverse_of: :classrooms
  has_many :students,
           dependent: :restrict_with_error,
           inverse_of: :classroom

  scope :in_school_order, -> {
    order(:school_year, :grade)
      .order(Arel.sql("CASE WHEN classrooms.class_label ~ '^[0-9]+$' THEN 0 ELSE 1 END"))
      .order(Arel.sql("CASE WHEN classrooms.class_label ~ '^[0-9]+$' THEN classrooms.class_label::numeric END"))
      .order(:class_label)
  }

  before_validation :normalize_class_label

  validates :school, presence: true
  validates :name, presence: true
  validates :school_year,
            :grade,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :class_label,
            presence: true,
            length: { maximum: 30 },
            uniqueness: { scope: %i[school_id school_year grade] }
  validates :active, inclusion: { in: [true, false] }
  validates :teacher_id,
            uniqueness: { conditions: -> { where(active: true) } },
            allow_nil: true,
            if: :active?

  validate :teacher_must_be_teacher
  validate :teacher_must_belong_to_school
  validate :school_cannot_change, on: :update

  def formatted_class_label
    label = class_label.to_s
    label.match?(/\A\d+\z/) ? "#{label}반" : label
  end

  private

  def normalize_class_label
    self.class_label = class_label.to_s.strip.presence
  end

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
