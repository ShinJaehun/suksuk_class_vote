require "rails_helper"
require "ostruct"

RSpec.describe SchoolElections::ResultSummary do
  describe "#contest_results" do
    it "aggregates closed integrity-ok classroom polls by school election source links" do
      context = create_school_election_context
      first_poll = create_classroom_poll(context.school_election, group_name: "6학년 1반")
      second_poll = create_classroom_poll(context.school_election, group_name: "6학년 2반")
      close_poll_with_results(
        first_poll,
        votes: {
          context.president_kim => 1,
          context.sixth_vice_lee => 1
        }
      )
      close_poll_with_results(
        second_poll,
        votes: {
          context.president_park => 1
        },
        abstentions: {
          context.sixth_vice => 1
        }
      )

      summary = described_class.new(context.school_election)

      expect(summary.contest_results.map { |result| result.school_election_contest.title }).to eq(["회장", "6학년 부회장"])
      president_result, sixth_vice_result = summary.contest_results
      expect(president_result.candidate_results.map { |result| result.school_election_candidate.name }).to eq(["김회장", "박회장"])
      expect(president_result.candidate_results.map(&:votes_count)).to eq([1, 1])
      expect(sixth_vice_result.candidate_results.map(&:votes_count)).to eq([1, 0])
      expect(sixth_vice_result.abstentions_count).to eq(1)
      expect(sixth_vice_result.decisions_count).to eq(2)
      expect(first_poll.poll_options.find_by!(school_election_candidate: context.president_kim).id).not_to eq(
        second_poll.poll_options.find_by!(school_election_candidate: context.president_kim).id
      )
    end

    it "aggregates abstentions by school election contest source links across cloned poll contests" do
      context = create_school_election_context
      first_poll = create_classroom_poll(context.school_election, group_name: "6학년 1반")
      second_poll = create_classroom_poll(context.school_election, group_name: "6학년 2반")
      close_poll_with_results(first_poll, votes: { context.president_kim => 1 }, abstentions: { context.sixth_vice => 1 })
      close_poll_with_results(second_poll, votes: { context.president_park => 1 }, abstentions: { context.sixth_vice => 1 })

      sixth_vice_result = described_class.new(context.school_election).contest_results.second

      expect(sixth_vice_result.abstentions_count).to eq(2)
      expect(first_poll.poll_contests.find_by!(school_election_contest: context.sixth_vice).id).not_to eq(
        second_poll.poll_contests.find_by!(school_election_contest: context.sixth_vice).id
      )
    end

    it "excludes unavailable and integrity-issue sessions from aggregation" do
      context = create_school_election_context
      missing_poll_session = create_session(context.school_election, group_name: "6학년 1반")
      draft_poll = create_classroom_poll(context.school_election, group_name: "6학년 2반")
      in_progress_poll = create_classroom_poll(context.school_election, group_name: "6학년 3반")
      in_progress_poll.update!(status: :in_progress)
      issue_poll = create_classroom_poll(context.school_election, group_name: "6학년 4반")
      close_poll_with_results(issue_poll, votes: {}, integrity_ok: false)
      ok_poll = create_classroom_poll(context.school_election, group_name: "6학년 5반")
      close_poll_with_results(ok_poll, votes: { context.president_kim => 1, context.sixth_vice_lee => 1 })

      summary = described_class.new(context.school_election)
      president_result = summary.contest_results.first

      expect(president_result.candidate_results.map(&:votes_count)).to eq([1, 0])
      expect(summary.missing_poll_sessions).to contain_exactly(missing_poll_session)
      expect(summary.not_closed_sessions.map(&:poll)).to contain_exactly(draft_poll, in_progress_poll)
      expect(summary.integrity_issue_sessions.map(&:poll)).to contain_exactly(issue_poll)
      expect(summary.closed_ok_sessions.map(&:poll)).to contain_exactly(ok_poll)
      expect(summary.blocking_sessions).to match_array([missing_poll_session, draft_poll.school_election_classroom_session, in_progress_poll.school_election_classroom_session, issue_poll.school_election_classroom_session])
      expect(summary.ready_for_final_count?).to be(false)
    end

    it "is ready for final count only when every session is closed and integrity-ok" do
      context = create_school_election_context
      first_poll = create_classroom_poll(context.school_election, group_name: "6학년 1반")
      second_poll = create_classroom_poll(context.school_election, group_name: "6학년 2반")
      close_poll_with_results(first_poll, votes: { context.president_kim => 1, context.sixth_vice_lee => 1 })
      close_poll_with_results(second_poll, votes: { context.president_park => 1 }, abstentions: { context.sixth_vice => 1 })

      expect(described_class.new(context.school_election)).to be_ready_for_final_count
      expect(described_class.new(create(:school_election))).not_to be_ready_for_final_count
    end

    it "selects top candidates by candidate votes only" do
      context = create_school_election_context
      poll = create_classroom_poll(context.school_election, group_name: "6학년 1반", voter_count: 4)
      close_poll_with_results(
        poll,
        votes: {
          context.president_kim => 1,
          context.president_park => 1,
          context.sixth_vice_lee => 4
        },
        abstentions: {
          context.president => 2
        },
        participant_count: 4
      )

      president_result = described_class.new(context.school_election).contest_results.first

      expect(president_result.abstentions_count).to eq(2)
      expect(president_result.top_candidate_results.map(&:school_election_candidate)).to match_array([
        context.president_kim,
        context.president_park
      ])
    end
  end

  def create_school_election_context
    school_election = create(:school_election)
    president = create(:school_election_contest, school_election: school_election, position: 1, title: "회장")
    sixth_vice = create(:school_election_contest, school_election: school_election, position: 2, title: "6학년 부회장")
    president_kim = create(:school_election_candidate, school_election_contest: president, number: 1, name: "김회장")
    president_park = create(:school_election_candidate, school_election_contest: president, number: 2, name: "박회장")
    sixth_vice_lee = create(:school_election_candidate, school_election_contest: sixth_vice, number: 1, name: "이부회장")
    sixth_vice_choi = create(:school_election_candidate, school_election_contest: sixth_vice, number: 2, name: "최부회장")

    OpenStruct.new(
      school_election: school_election,
      president: president,
      sixth_vice: sixth_vice,
      president_kim: president_kim,
      president_park: president_park,
      sixth_vice_lee: sixth_vice_lee,
      sixth_vice_choi: sixth_vice_choi
    )
  end

  def create_classroom_poll(school_election, group_name:, voter_count: 1)
    session = create_session(school_election, group_name: group_name, voter_count: voter_count)
    result = SchoolElections::CreateClassroomPoll.new(session).call

    result.poll
  end

  def create_session(school_election, group_name:, voter_count: 1)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher, name: group_name)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1, name: "학생#{index + 1}")
    end
    create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: participant_group)
  end

  def close_poll_with_results(poll, votes:, abstentions: {}, participant_count: 1, integrity_ok: true)
    create_poll_participants(poll, participant_count)
    poll.poll_options.find_each do |poll_option|
      create(:poll_option_tally, poll: poll, poll_option: poll_option, votes_count: votes.fetch(poll_option.school_election_candidate, 0))
    end
    poll.poll_contests.find_each do |poll_contest|
      create(:poll_contest_tally, poll: poll, poll_contest: poll_contest, abstentions_count: abstentions.fetch(poll_contest.school_election_contest, 0))
    end
    create(:poll_progress, poll: poll, status: :closed, ballot_status: :ballot_locked, current_poll_participant: nil)
    poll.update!(status: :closed)

    return poll.reload unless integrity_ok

    poll.poll_participants.order(:number).each do |poll_participant|
      create(:poll_participation, poll_participant: poll_participant)
    end
    poll.reload
  end

  def create_poll_participants(poll, participant_count)
    poll.participant_group.participant_slots.order(:number).first(participant_count).each do |participant_slot|
      create(
        :poll_participant,
        poll: poll,
        source_participant_slot: participant_slot,
        number: participant_slot.number,
        name: participant_slot.name
      )
    end
  end
end
