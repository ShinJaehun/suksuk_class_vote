FactoryBot.define do
  factory :participant_group do
    association :user
    name { "4학년 1반" }
    purpose { :teacher_personal }

    trait :school_election do
      purpose { :school_election }
      school_name { "쑥쑥초등학교" }
      grade { 4 }
      class_number { 1 }
    end

    trait :with_participant_slot do
      after(:create) do |participant_group|
        create(:participant_slot, participant_group: participant_group)
      end
    end
  end
end
