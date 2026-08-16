FactoryBot.define do
  factory :poll_contest_tally do
    association :poll_session
    poll { poll_session.poll }
    poll_contest { association(:poll_contest, poll: poll) }
    abstentions_count { 0 }
  end
end
