FactoryBot.define do
  factory :poll_option_tally do
    association :poll_option
    poll { poll_option.poll }
    votes_count { 0 }
  end
end
