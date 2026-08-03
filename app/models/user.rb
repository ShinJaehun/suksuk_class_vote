class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  enum :role, { teacher: 0, admin: 10 }

  has_one :school_membership, dependent: :destroy
  has_one :school, through: :school_membership
  has_many :classrooms,
           foreign_key: :teacher_id,
           dependent: :nullify,
           inverse_of: :teacher
  has_one :active_classroom,
          -> { where(active: true) },
          class_name: "Classroom",
          foreign_key: :teacher_id
  has_many :participant_groups, dependent: :destroy
  has_many :polls, dependent: :destroy
  has_many :operated_poll_sessions,
           class_name: "PollSession",
           foreign_key: :operator_id,
           inverse_of: :operator,
           dependent: :restrict_with_error
  has_many :poll_events, foreign_key: :actor_id, dependent: :nullify, inverse_of: :actor

  validates :name, presence: true
  validates :role, presence: true
end
