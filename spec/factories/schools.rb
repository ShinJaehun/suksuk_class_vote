FactoryBot.define do
  factory :school do
    sequence(:name) { |n| "쑥쑥초등학교#{n}" }
  end
end
