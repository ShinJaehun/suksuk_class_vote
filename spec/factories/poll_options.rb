FactoryBot.define do
  factory :poll_option do
    association :poll
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
  end
end
