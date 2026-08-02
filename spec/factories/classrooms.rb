FactoryBot.define do
  factory :classroom do
    association :school
    sequence(:name) { |n| "#{n}반" }

    trait :with_teacher do
      after(:build) do |classroom|
        teacher = create(:user)
        create(:school_membership, school: classroom.school, user: teacher)
        classroom.teacher = teacher
      end
    end
  end
end
