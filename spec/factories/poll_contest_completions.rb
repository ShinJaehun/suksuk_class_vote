FactoryBot.define do
  factory :poll_contest_completion do
    association :poll_participant
    poll_contest { poll_participant.poll.default_poll_contest }
    completed_at { Time.current }
  end
end
