FactoryBot.define do
  factory :poll_progress do
    association :poll_session
    poll { poll_session.poll }
    current_poll_participant { nil }
    status { :active }
    started_at { Time.current }
  end
end
