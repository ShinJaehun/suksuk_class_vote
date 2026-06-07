FactoryBot.define do
  factory :election_voter do
    transient do
      teacher { association(:user) }
      voter_group { create(:voter_group, user: teacher) }
    end

    source_voter_slot { create(:voter_slot, voter_group: voter_group) }
    election { create(:election, user: teacher, voter_group: voter_group) }
    sequence(:number) { |n| source_voter_slot&.number || n }
    name { source_voter_slot&.name || "선거 당시 이름" }
  end
end
