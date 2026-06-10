FactoryBot.define do
  factory :participant_slot do
    association :participant_group
    sequence(:number) { |n| n }
    name { "학생#{number}" }
  end
end
