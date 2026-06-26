FactoryBot.define do
  sequence(:school_election_class_label) { |n| n.to_s }

  factory :participant_group do
    association :user
    name { "4학년 1반" }
    purpose { :teacher_personal }

    trait :school_election do
      purpose { :school_election }
      association :school
      grade { 4 }
      class_number { 1 }
      class_label { generate(:school_election_class_label) }
      name { nil }
    end

    trait :with_participant_slot do
      after(:create) do |participant_group|
        create(:participant_slot, participant_group: participant_group)
      end
    end
  end
end
