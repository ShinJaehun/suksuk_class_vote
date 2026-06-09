FactoryBot.define do
  factory :polling_station do
    association :poll, status: :in_progress
    current_poll_participant { nil }
    status { :active }
    started_at { Time.current }
  end
end
