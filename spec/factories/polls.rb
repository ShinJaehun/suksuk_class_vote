FactoryBot.define do
  factory :poll do
    association :user
    title { "4학년 1반 반장 선거" }
    status { :draft }
    participant_group { create(:participant_group, :with_participant_slot, user: user) }

    trait :discussion do
      kind { :discussion }
    end

    trait :debate do
      kind { :debate }
    end
  end
end
