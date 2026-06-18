FactoryBot.define do
  factory :election_participation do
    association :election_voter
    status { :pending }
  end
end
