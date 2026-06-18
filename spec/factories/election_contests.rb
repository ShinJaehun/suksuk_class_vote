FactoryBot.define do
  factory :election_contest do
    association :election
    position { election.present? ? election.election_contests.maximum(:position).to_i + 1 : 1 }
    title { "Contest #{position}" }
    vote_method { :single_choice }
    min_selections { 1 }
    max_selections { 1 }
    seats_count { 1 }
    allow_abstain { true }
  end
end
