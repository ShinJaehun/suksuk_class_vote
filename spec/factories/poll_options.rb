FactoryBot.define do
  factory :poll_option do
    association :poll
    poll_contest { poll.default_poll_contest || poll.poll_contests.build(title: "기본", position: 1) if poll.present? }
    sequence(:number) { |n| n }
    name { "후보자#{number}" }
  end
end
