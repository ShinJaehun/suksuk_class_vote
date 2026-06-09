FactoryBot.define do
  factory :election_event do
    association :poll
    actor { poll.user }
    event_type { "election_started" }
    details { {} }
    occurred_at { Time.current }
  end
end
