FactoryBot.define do
  factory :election_session do
    association :election
    association :teacher, factory: :user
    participant_group do
      group_school = election&.school || create(:school)
      create(:participant_group, :school_election, user: teacher, school: group_school)
    end
    status { :draft }
    operation_mode { :supervised }
  end
end
