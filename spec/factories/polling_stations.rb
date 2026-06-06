FactoryBot.define do
  factory :polling_station do
    association :election, status: :in_progress
    current_election_voter { nil }
    status { :active }
    started_at { Time.current }
  end
end
