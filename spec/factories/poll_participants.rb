FactoryBot.define do
  factory :poll_participant do
    transient do
      teacher { association(:user) }
      participant_group { create(:participant_group, user: teacher) }
    end

    source_participant_slot { create(:participant_slot, participant_group: participant_group) }
    poll { create(:poll, user: teacher, participant_group: participant_group) }
    sequence(:number) { |n| source_participant_slot&.number || n }
    name { source_participant_slot&.name || "투표 당시 이름" }
  end
end
