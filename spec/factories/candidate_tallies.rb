FactoryBot.define do
  factory :candidate_tally do
    association :candidate
    election { candidate.election }
    votes_count { 0 }
  end
end
