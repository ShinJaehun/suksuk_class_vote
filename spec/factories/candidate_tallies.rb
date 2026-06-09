FactoryBot.define do
  factory :candidate_tally do
    association :candidate
    poll { candidate.poll }
    votes_count { 0 }
  end
end
