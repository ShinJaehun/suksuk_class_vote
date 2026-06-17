FactoryBot.define do
  factory :school_election_contest do
    association :school_election
    position { school_election.present? ? school_election.school_election_contests.maximum(:position).to_i + 1 : 1 }
    title { "Contest #{position}" }
  end
end
