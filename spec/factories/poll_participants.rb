FactoryBot.define do
  factory :poll_participant do
    poll_session
    poll { poll_session.poll }
    sequence(:number)
    name { "투표 당시 이름" }
  end
end
