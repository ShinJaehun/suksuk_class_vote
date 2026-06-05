FactoryBot.define do
  factory :candidate do
    association :election
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
  end
end
