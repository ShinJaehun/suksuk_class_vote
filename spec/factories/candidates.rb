FactoryBot.define do
  factory :candidate do
    association :poll
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
  end
end
