FactoryBot.define do
  factory :election_progress do
    association :election_session
    current_election_voter { nil }
    ballot_state { :locked }

    trait :with_current_voter do
      current_election_voter do
        create(
          :election_voter,
          election_session: election_session,
          teacher: election_session.teacher,
          participant_group: election_session.participant_group
        )
      end
    end
  end
end
