FactoryBot.define do
  factory :election_session do
    association :election
    association :teacher, factory: :user
    participant_group { create(:participant_group, user: teacher) }
    status { :draft }
    operation_mode { :supervised }
  end
end
