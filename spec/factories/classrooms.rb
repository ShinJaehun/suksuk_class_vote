FactoryBot.define do
  factory :classroom do
    association :school
    school_year { 2026 }
    grade { 4 }
    sequence(:class_number) { |n| n }
    name { "#{grade}학년 #{class_number}반" }
    active { true }

    trait :with_teacher do
      after(:build) do |classroom|
        teacher = create(:user)
        create(:school_membership, school: classroom.school, user: teacher)
        classroom.teacher = teacher
      end
    end
  end
end
