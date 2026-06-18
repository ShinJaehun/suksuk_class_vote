FactoryBot.define do
  factory :election_candidate_tally do
    transient do
      election { create(:election) }
    end

    election_session { create(:election_session, election: election) }
    election_contest { create(:election_contest, election: election) }
    election_candidate { election_contest.present? ? create(:election_candidate, election_contest: election_contest) : nil }
    votes_count { 0 }
  end
end
