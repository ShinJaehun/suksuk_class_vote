FactoryBot.define do
  factory :voter_slot do
    association :voter_group
    sequence(:number) { |n| n }
    name { "학생#{number}" }
  end
end
