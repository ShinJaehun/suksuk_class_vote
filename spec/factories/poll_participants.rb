FactoryBot.define do
  factory :poll_participant do
    transient do
      teacher { association(:user) }
      voter_group { create(:voter_group, user: teacher) }
    end

    source_voter_slot { create(:voter_slot, voter_group: voter_group) }
    poll { create(:poll, user: teacher, voter_group: voter_group) }
    sequence(:number) { |n| source_voter_slot&.number || n }
    name { source_voter_slot&.name || "투표 당시 이름" }
  end
end
