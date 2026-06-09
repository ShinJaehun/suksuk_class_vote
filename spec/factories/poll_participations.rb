FactoryBot.define do
  factory :poll_participation do
    association :poll_participant
    status { :completed }
    recorded_at { Time.current }
  end
end
