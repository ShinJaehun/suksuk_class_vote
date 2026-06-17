FactoryBot.define do
  factory :school_election_classroom_session do
    association :school_election
    association :teacher, factory: :user
    participant_group { create(:participant_group, :with_participant_slot, user: teacher) }
    poll { nil }
  end
end
