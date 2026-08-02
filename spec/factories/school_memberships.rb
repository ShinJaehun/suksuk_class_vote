FactoryBot.define do
  factory :school_membership do
    association :school
    association :user
    role { :member }

    trait :manager do
      role { :manager }
    end
  end
end
