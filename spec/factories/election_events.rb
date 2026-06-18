FactoryBot.define do
  factory :election_event do
    association :election_session
    association :actor, factory: :user
    election_voter { nil }
    event_type { :session_started }
    metadata { {} }
    occurred_at { Time.current }

    trait :with_voter do
      after(:build) do |event|
        session = event.election_session&.persisted? ? event.election_session : create(:election_session)
        event.election_session = session
        event.election_voter ||= create(
          :election_voter,
          election_session: session,
          teacher: session.teacher,
          participant_group: session.participant_group
        )
      end
    end

    trait :ballot_submitted do
      event_type { :ballot_submitted }
    end
  end
end
