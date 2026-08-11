class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  enum :role, { teacher: 0, admin: 10 }

  before_validation :normalize_login_id
  before_validation :normalize_email

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
  validates :login_id, presence: true, uniqueness: { case_sensitive: false }
  validates :email, presence: true, if: :admin?
  validate :password_must_differ_from_login_id

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive
  end

  def email_required?
    admin?
  end

  private

  def normalize_login_id
    self.login_id = login_id.to_s.strip.downcase.presence
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def password_must_differ_from_login_id
    return if password.blank? || login_id.blank? || password != login_id

    errors.add(:password, "는 로그인 ID와 달라야 합니다")
  end
end
