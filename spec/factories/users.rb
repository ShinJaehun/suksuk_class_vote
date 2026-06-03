FactoryBot.define do
  factory :user do
    name { "테스트 교사" }
    sequence(:email) { |n| "teacher#{n}@example.com" }
    password { "password123!" }
    role { :teacher }

    trait :admin do
      name { "관리자" }
      role { :admin }
    end
  end
end
