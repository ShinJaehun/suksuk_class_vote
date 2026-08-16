FactoryBot.define do
  factory :poll do
    association :user
    association :school
    title { "4학년 1반 반장 선거" }
    status { :draft }

    trait :discussion do
      kind { :discussion }
    end

    trait :debate do
      kind { :debate }
    end
  end
end
