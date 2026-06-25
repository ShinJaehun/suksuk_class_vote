FactoryBot.define do
  factory :election_voter do
    transient do
      teacher { association(:user) }
      participant_group { create(:participant_group, :school_election, user: teacher) }
    end

    source_participant_slot { create(:participant_slot, participant_group: participant_group) }
    election_session { create(:election_session, teacher: teacher, participant_group: participant_group) }
    number { source_participant_slot&.number || 1 }
    name { source_participant_slot&.name || "투표 당시 이름" }
    position { number }
  end
end
