FactoryBot.define do
  factory :poll_option_tally do
    association :poll_session
    poll { poll_session.poll }
    poll_option { association(:poll_option, poll: poll) }
    votes_count { 0 }
  end
end
