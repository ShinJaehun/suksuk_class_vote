FactoryBot.define do
  factory :participant_group do
    association :user
    name { "4학년 1반" }

    trait :with_participant_slot do
      after(:create) do |participant_group|
        create(:participant_slot, participant_group: participant_group)
      end
    end
  end
end
