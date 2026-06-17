FactoryBot.define do
  factory :school_election_candidate do
    association :school_election_contest
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
    grade_class_label { "6학년 1반" }
  end
end
