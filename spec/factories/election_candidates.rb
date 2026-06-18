FactoryBot.define do
  factory :election_candidate do
    association :election_contest
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
    affiliation_label { "6학년 1반" }
  end
end
