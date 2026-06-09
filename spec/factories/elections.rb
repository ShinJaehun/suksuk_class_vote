FactoryBot.define do
  factory :election do
    association :user
    title { "4학년 1반 반장 선거" }
    status { :draft }
    voter_group { create(:voter_group, :with_voter_slot, user: user) }

    trait :discussion do
      kind { :discussion }
    end

    trait :debate do
      kind { :debate }
    end
  end
end
