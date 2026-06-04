FactoryBot.define do
  factory :voter_group do
    association :user
    name { "4학년 1반" }

    trait :with_voter_slot do
      after(:create) do |voter_group|
        create(:voter_slot, voter_group: voter_group)
      end
    end
  end
end
