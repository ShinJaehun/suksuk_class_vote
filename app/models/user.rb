class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  enum :role, { teacher: 0, admin: 10 }

  has_many :voter_groups, dependent: :destroy
  has_many :elections, dependent: :destroy
  has_many :election_events, foreign_key: :actor_id, dependent: :nullify, inverse_of: :actor

  validates :name, presence: true
  validates :role, presence: true
end
