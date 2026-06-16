FactoryBot.define do
  factory :poll_contest do
    association :poll
    position { poll.present? ? poll.poll_contests.maximum(:position).to_i + 1 : 1 }
    title { "Contest #{position}" }
  end
end
