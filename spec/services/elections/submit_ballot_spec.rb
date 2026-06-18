require "rails_helper"

RSpec.describe Elections::SubmitBallot do
  describe "#call" do
    it "submits one candidate for a single choice contest" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      contest = setup.contests.first
      selected_candidate = contest.election_candidates.order(:number).first
      other_candidate = contest.election_candidates.order(:number).second
      current_voter = setup.session.election_progress.current_election_voter

      result = submit(setup, selections: { contest.id => selected_candidate.id })

      expect(result).to be_success
      expect(tally_for(setup.session, selected_candidate).reload.votes_count).to eq(1)
      expect(tally_for(setup.session, other_candidate).reload.votes_count).to eq(0)
      expect(current_voter.election_participation.reload).to be_completed
      expect(current_voter.election_participation.submitted_at).to be_present
      expect(setup.session.election_progress.reload).to be_locked
      expect(setup.session.election_progress.current_election_voter).to eq(current_voter)

      event = setup.session.election_events.where(event_type: :ballot_submitted).sole
      expect(event.election_voter).to eq(current_voter)
      expect(event.metadata).to include(
        "voter_id" => current_voter.id,
        "voter_number" => current_voter.number,
        "voter_position" => current_voter.position,
        "contest_count" => 1,
        "voted_contest_count" => 1,
        "abstained_contest_count" => 0,
        "all_contests_abstained" => false
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "selected_candidates", "choices", "ballot_choices")
    end

    it "submits multiple candidates for a limited choice contest" do
      setup = open_session_with_contests([{ vote_method: :limited_choice, candidate_count: 3, min_selections: 1, max_selections: 2, seats_count: 2 }])
      contest = setup.contests.first
      selected_candidates = contest.election_candidates.order(:number).first(2)

      result = submit(setup, selections: { contest.id => selected_candidates.map(&:id) })

      expect(result).to be_success
      expect(selected_candidates.map { |candidate| tally_for(setup.session, candidate).reload.votes_count }).to eq([1, 1])
    end

    it "submits a multi contest ballot" do
      setup = open_session_with_contests([
        { vote_method: :single_choice, candidate_count: 2 },
        { vote_method: :limited_choice, candidate_count: 3, min_selections: 1, max_selections: 2, seats_count: 2 }
      ])
      first_candidate = setup.contests.first.election_candidates.order(:number).first
      second_candidates = setup.contests.second.election_candidates.order(:number).first(2)

      result = submit(
        setup,
        selections: {
          setup.contests.first.id => first_candidate.id,
          setup.contests.second.id => second_candidates.map(&:id)
        }
      )

      expect(result).to be_success
      expect(tally_for(setup.session, first_candidate).reload.votes_count).to eq(1)
      expect(second_candidates.map { |candidate| tally_for(setup.session, candidate).reload.votes_count }).to eq([1, 1])
    end

    it "records abstention for an abstained contest" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2, allow_abstain: true }])
      contest = setup.contests.first

      result = submit(setup, selections: {}, abstained_contest_ids: [contest.id])

      expect(result).to be_success
      expect(contest_tally_for(setup.session, contest).reload.abstentions_count).to eq(1)
    end

    it "marks participation abstained when every contest is abstained" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2, allow_abstain: true }])
      current_voter = setup.session.election_progress.current_election_voter

      result = submit(setup, selections: {}, abstained_contest_ids: setup.contests.map(&:id))

      expect(result).to be_success
      expect(current_voter.election_participation.reload).to be_abstained
    end

    it "marks participation completed when at least one contest has a candidate selection" do
      setup = open_session_with_contests([
        { vote_method: :single_choice, candidate_count: 2, allow_abstain: true },
        { vote_method: :single_choice, candidate_count: 2, allow_abstain: true }
      ])
      selected_candidate = setup.contests.first.election_candidates.order(:number).first
      current_voter = setup.session.election_progress.current_election_voter

      result = submit(
        setup,
        selections: { setup.contests.first.id => selected_candidate.id },
        abstained_contest_ids: [setup.contests.second.id]
      )

      expect(result).to be_success
      expect(current_voter.election_participation.reload).to be_completed
      expect(contest_tally_for(setup.session, setup.contests.second).reload.abstentions_count).to eq(1)
    end

    it "normalizes string keys and string candidate ids" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      contest = setup.contests.first
      selected_candidate = contest.election_candidates.order(:number).first

      result = submit(setup, selections: { contest.id.to_s => selected_candidate.id.to_s })

      expect(result).to be_success
      expect(tally_for(setup.session, selected_candidate).reload.votes_count).to eq(1)
    end

    it "fails without an actor" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      contest = setup.contests.first
      selected_candidate = contest.election_candidates.order(:number).first

      result = described_class.new(
        election_session: setup.session,
        actor: nil,
        selections_by_contest_id: { contest.id => selected_candidate.id },
        abstained_contest_ids: []
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
      expect_no_submission(setup)
    end

    it "fails unless session is in progress" do
      %i[draft closed stopped].each do |status|
        setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
        setup.session.update!(status: status)

        result = submit_valid_single_choice(setup)

        expect(result).not_to be_success
        expect_no_submission(setup, expected_ballot_state: :open)
      end
    end

    it "fails for pin login sessions" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      setup.session.update!(operation_mode: :pin_login)

      result = submit_valid_single_choice(setup)

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
      expect_no_submission(setup)
    end

    it "fails without progress" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      setup.session.election_progress.destroy!

      result = submit_valid_single_choice(setup)

      expect(result).not_to be_success
      expect(setup.session.election_events.where(event_type: :ballot_submitted)).to be_empty
    end

    it "fails without current voter" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      setup.session.election_progress.update!(current_election_voter: nil)

      result = submit_valid_single_choice(setup)

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 없습니다.")
      expect(setup.session.election_events.where(event_type: :ballot_submitted)).to be_empty
    end

    it "fails when ballot is locked" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      setup.session.election_progress.update!(ballot_state: :locked)

      result = submit_valid_single_choice(setup)

      expect(result).not_to be_success
      expect(result.error_message).to include("ballot이 열려 있어야 제출할 수 있습니다.")
      expect_no_submission(setup, expected_ballot_state: :locked)
    end

    it "fails without participation" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      setup.session.election_progress.current_election_voter.election_participation.destroy!

      result = submit_valid_single_choice(setup)

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자의 참여 정보가 없습니다.")
      expect(setup.session.election_events.where(event_type: :ballot_submitted)).to be_empty
    end

    it "fails when participation is already final" do
      %i[completed absent abstained].each do |status|
        setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
        setup.session.election_progress.current_election_voter.election_participation.update!(status: status, submitted_at: Time.current)

        result = submit_valid_single_choice(setup)

        expect(result).not_to be_success
        expect(result.error_message).to include("대기 중인 투표자만 제출할 수 있습니다.")
        expect(setup.session.election_events.where(event_type: :ballot_submitted)).to be_empty
      end
    end

    it "fails when selections are not a hash" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])

      result = described_class.new(
        election_session: setup.session,
        actor: setup.session.teacher,
        selections_by_contest_id: "bad",
        abstained_contest_ids: []
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("제출 데이터가 올바르지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails when a contest is missing" do
      setup = open_session_with_contests([
        { vote_method: :single_choice, candidate_count: 2 },
        { vote_method: :single_choice, candidate_count: 2 }
      ])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { setup.contests.first.id => candidate.id })

      expect(result).not_to be_success
      expect(result.error_message).to include("제출되지 않은 선거 항목")
      expect_no_submission(setup)
    end

    it "fails with an unknown contest id" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { 99_999 => candidate.id }, abstained_contest_ids: [setup.contests.first.id])

      expect(result).not_to be_success
      expect(result.error_message).to include("알 수 없는 선거 항목")
      expect_no_submission(setup)
    end

    it "fails with a contest from another election" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      other_contest = create(:election_contest)
      other_candidate = create(:election_candidate, election_contest: other_contest)

      result = submit(setup, selections: { other_contest.id => other_candidate.id }, abstained_contest_ids: [setup.contests.first.id])

      expect(result).not_to be_success
      expect(result.error_message).to include("알 수 없는 선거 항목")
      expect_no_submission(setup)
    end

    it "fails when candidate does not belong to contest" do
      setup = open_session_with_contests([
        { vote_method: :single_choice, candidate_count: 2 },
        { vote_method: :single_choice, candidate_count: 2 }
      ])
      wrong_candidate = setup.contests.second.election_candidates.order(:number).first

      result = submit(
        setup,
        selections: { setup.contests.first.id => wrong_candidate.id },
        abstained_contest_ids: [setup.contests.second.id]
      )

      expect(result).not_to be_success
      expect(result.error_message).to include("후보자가 해당 선거 항목에 속하지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails when same candidate is selected twice" do
      setup = open_session_with_contests([{ vote_method: :limited_choice, candidate_count: 2, min_selections: 1, max_selections: 2, seats_count: 2 }])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { setup.contests.first.id => [candidate.id, candidate.id] })

      expect(result).not_to be_success
      expect(result.error_message).to include("같은 후보를 중복 선택할 수 없습니다.")
      expect_no_submission(setup)
    end

    it "fails when selection and abstain are both submitted" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { setup.contests.first.id => candidate.id }, abstained_contest_ids: [setup.contests.first.id])

      expect(result).not_to be_success
      expect(result.error_message).to include("선택과 기권을 동시에 제출할 수 없습니다.")
      expect_no_submission(setup)
    end

    it "fails when abstain is not allowed" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2, allow_abstain: false }])

      result = submit(setup, selections: {}, abstained_contest_ids: [setup.contests.first.id])

      expect(result).not_to be_success
      expect(result.error_message).to include("기권할 수 없는 선거 항목")
      expect_no_submission(setup)
    end

    it "fails when single choice has no selection" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2, allow_abstain: false }])

      result = submit(setup, selections: { setup.contests.first.id => "" })

      expect(result).not_to be_success
      expect(result.error_message).to include("제출되지 않은 선거 항목")
      expect_no_submission(setup)
    end

    it "fails when single choice has two selections" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      candidates = setup.contests.first.election_candidates.order(:number).to_a

      result = submit(setup, selections: { setup.contests.first.id => candidates.map(&:id) })

      expect(result).not_to be_success
      expect(result.error_message).to include("선택 가능한 후보 수가 올바르지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails when limited choice is below min selections" do
      setup = open_session_with_contests([{ vote_method: :limited_choice, candidate_count: 3, min_selections: 2, max_selections: 3, seats_count: 3 }])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { setup.contests.first.id => candidate.id })

      expect(result).not_to be_success
      expect(result.error_message).to include("선택 가능한 후보 수가 올바르지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails when limited choice exceeds max selections" do
      setup = open_session_with_contests([{ vote_method: :limited_choice, candidate_count: 3, min_selections: 1, max_selections: 2, seats_count: 2 }])
      candidates = setup.contests.first.election_candidates.order(:number).to_a

      result = submit(setup, selections: { setup.contests.first.id => candidates.map(&:id) })

      expect(result).not_to be_success
      expect(result.error_message).to include("선택 가능한 후보 수가 올바르지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails when approval is outside min max range" do
      setup = open_session_with_contests([{ vote_method: :approval, candidate_count: 2, min_selections: 1, max_selections: 1 }])
      candidates = setup.contests.first.election_candidates.order(:number).to_a

      result = submit(setup, selections: { setup.contests.first.id => candidates.map(&:id) })

      expect(result).not_to be_success
      expect(result.error_message).to include("선택 가능한 후보 수가 올바르지 않습니다.")
      expect_no_submission(setup)
    end

    it "fails for yes no contests" do
      setup = open_session_with_contests([{ vote_method: :yes_no, candidate_count: 1 }])
      candidate = setup.contests.first.election_candidates.order(:number).first

      result = submit(setup, selections: { setup.contests.first.id => candidate.id })

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 투표 방식")
      expect_no_submission(setup)
    end

    it "fails when candidate tally is missing" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      candidate = setup.contests.first.election_candidates.order(:number).first
      tally_for(setup.session, candidate).destroy!

      result = submit(setup, selections: { setup.contests.first.id => candidate.id })

      expect(result).not_to be_success
      expect(result.error_message).to include("후보별 집계 정보를 찾을 수 없습니다.")
      expect_no_submission(setup)
    end

    it "fails when contest tally is missing" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2, allow_abstain: true }])
      contest_tally_for(setup.session, setup.contests.first).destroy!

      result = submit(setup, selections: {}, abstained_contest_ids: [setup.contests.first.id])

      expect(result).not_to be_success
      expect(result.error_message).to include("선거 항목별 기권 집계 정보를 찾을 수 없습니다.")
      expect_no_submission(setup)
    end

    it "prevents duplicate submission for the same current voter" do
      setup = open_session_with_contests([{ vote_method: :single_choice, candidate_count: 2 }])
      contest = setup.contests.first
      selected_candidate = contest.election_candidates.order(:number).first

      first_result = submit(setup, selections: { contest.id => selected_candidate.id })
      second_result = submit(setup, selections: { contest.id => selected_candidate.id })

      expect(first_result).to be_success
      expect(second_result).not_to be_success
      expect(tally_for(setup.session, selected_candidate).reload.votes_count).to eq(1)
      expect(setup.session.election_events.where(event_type: :ballot_submitted).count).to eq(1)
    end
  end

  Setup = Struct.new(:session, :contests, keyword_init: true)

  def open_session_with_contests(contest_configs)
    election = create(:election)
    contests = contest_configs.each_with_index.map do |config, index|
      contest = create(
        :election_contest,
        election: election,
        position: index + 1,
        vote_method: config.fetch(:vote_method),
        min_selections: config.fetch(:min_selections, 1),
        max_selections: config.fetch(:max_selections, 1),
        seats_count: config.fetch(:seats_count, 1),
        allow_abstain: config.fetch(:allow_abstain, true)
      )
      create_list(:election_candidate, config.fetch(:candidate_count), election_contest: contest)
      contest
    end
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group)
    session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: session, actor: teacher).call
    Elections::OpenBallot.new(election_session: session, actor: teacher).call

    Setup.new(session: session.reload, contests: contests.map(&:reload))
  end

  def submit(setup, selections:, abstained_contest_ids: [])
    described_class.new(
      election_session: setup.session,
      actor: setup.session.teacher,
      selections_by_contest_id: selections,
      abstained_contest_ids: abstained_contest_ids
    ).call
  end

  def submit_valid_single_choice(setup)
    contest = setup.contests.first
    candidate = contest.election_candidates.order(:number).first
    submit(setup, selections: { contest.id => candidate.id })
  end

  def tally_for(session, candidate)
    session.election_candidate_tallies.find_by!(election_candidate: candidate)
  end

  def contest_tally_for(session, contest)
    session.election_contest_tallies.find_by!(election_contest: contest)
  end

  def expect_no_submission(setup, expected_ballot_state: :open)
    expect(setup.session.election_candidate_tallies.sum(:votes_count)).to eq(0)
    expect(setup.session.election_contest_tallies.sum(:abstentions_count)).to eq(0)
    participation = setup.session.election_progress&.current_election_voter&.election_participation
    expect(participation.reload).to be_pending if participation.present?
    expect(participation.submitted_at).to be_nil if participation.present?
    expect(setup.session.election_progress.reload.public_send("#{expected_ballot_state}?")).to be(true) if setup.session.election_progress.present?
    expect(setup.session.election_events.where(event_type: :ballot_submitted)).to be_empty
  end
end
