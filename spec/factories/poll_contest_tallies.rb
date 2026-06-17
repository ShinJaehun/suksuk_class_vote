FactoryBot.define do
  factory :poll_contest_tally do
    association :poll_contest
    poll { poll_contest.poll }
    abstentions_count { 0 }
  end
end
