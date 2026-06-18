FactoryBot.define do
  factory :election_contest_tally do
    transient do
      election { create(:election) }
    end

    election_session { create(:election_session, election: election) }
    election_contest { create(:election_contest, election: election) }
    abstentions_count { 0 }
  end
end
