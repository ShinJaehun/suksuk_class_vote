FactoryBot.define do
  factory :student do
    association :classroom
    sequence(:number) { |n| n }
    sequence(:name) { |n| "학생 #{n}" }
    active { true }
  end
end
