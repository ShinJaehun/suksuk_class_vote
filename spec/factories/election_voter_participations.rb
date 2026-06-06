FactoryBot.define do
  factory :election_voter_participation do
    association :election_voter
    status { :completed }
    recorded_at { Time.current }
  end
end
