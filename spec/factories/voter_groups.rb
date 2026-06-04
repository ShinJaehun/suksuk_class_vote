FactoryBot.define do
  factory :voter_group do
    association :user
    name { "4학년 1반" }
  end
end
