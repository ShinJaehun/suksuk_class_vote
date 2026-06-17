class SchoolElectionClassroomSession < ApplicationRecord
  belongs_to :school_election
  belongs_to :teacher, class_name: "User"
  belongs_to :participant_group
  belongs_to :poll, optional: true

  validates :school_election, presence: true
  validates :teacher, presence: true
  validates :participant_group, presence: true
  validates :participant_group_id, uniqueness: { scope: :school_election_id }
  validates :poll_id, uniqueness: true, allow_nil: true
  validate :participant_group_belongs_to_teacher

  private

  def participant_group_belongs_to_teacher
    return if participant_group.blank? || teacher.blank?
    return if participant_group.user_id == teacher.id

    errors.add(:participant_group, "must belong to teacher")
  end
end
