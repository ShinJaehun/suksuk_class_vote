FactoryBot.define do
  factory :classroom do
    association :school
    school_year { 2026 }
    grade { 4 }
    sequence(:class_label) { |n| n.to_s }
    name do
      label = class_label.to_s
      "#{grade}학년 #{label.match?(/\A\d+\z/) ? "#{label}반" : label}"
    end
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
