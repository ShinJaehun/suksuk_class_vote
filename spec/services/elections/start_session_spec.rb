require "rails_helper"

RSpec.describe Elections::StartSession do
  include ActionCable::TestHelper

  describe "#call" do
    it "starts a draft supervised election session" do
      election = create(:election)
      contest = create(:election_contest, election: election)
      candidates = create_list(:election_candidate, 2, election_contest: contest)
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      first_slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
      second_slot = create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
      election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

      result = described_class.new(election_session: election_session, actor: teacher).call

      expect(result).to be_success
      expect(election_session.reload).to be_in_progress
      expect(election_session.started_at).to be_present

      voters = election_session.election_voters.order(:position)
      expect(voters.size).to eq(2)
      expect(voters.first).to have_attributes(
        number: first_slot.number,
        name: first_slot.name,
        position: first_slot.number,
        source_participant_slot: first_slot
      )
      expect(voters.second).to have_attributes(
        number: second_slot.number,
        name: second_slot.name,
        position: second_slot.number,
        source_participant_slot: second_slot
      )
      expect(ElectionParticipation.where(election_voter: voters).pluck(:status)).to eq(%w[pending pending])

      progress = election_session.election_progress
      expect(progress.current_election_voter).to eq(voters.first)
      expect(progress).to be_locked
      expect(progress.started_at).to be_present

      expect(election_session.election_candidate_tallies.pluck(:election_candidate_id)).to match_array(candidates.map(&:id))
      expect(election_session.election_candidate_tallies.pluck(:votes_count)).to all(eq(0))
      expect(election_session.election_contest_tallies.pluck(:election_contest_id)).to eq([ contest.id ])
      expect(election_session.election_contest_tallies.pluck(:abstentions_count)).to eq([ 0 ])

      event = election_session.election_events.sole
      expect(event).to be_session_started
      expect(event.actor).to eq(teacher)
      expect(event.election_voter).to be_nil
      expect(event.metadata).to eq(
        "voter_count" => 2,
        "contest_count" => 1,
        "candidate_count" => 2,
        "operation_mode" => "supervised"
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "choices", "ballot_choices")
    end

    it "broadcasts the admin election overview after starting" do
      election = create(:election, status: :in_progress)
      contest = create(:election_contest, election: election)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      broadcasts = admin_overview_broadcasts_for(election_session.election)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_summary)) }).to be(true)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_status_report)) }).to be(true)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_sessions)) }).to be(true)
      expect(broadcasts.join).to include("진행 중")
    end

    it "creates tallies for every contest and candidate" do
      election = create(:election)
      president = create(:election_contest, election: election, position: 1)
      vice_president = create(:election_contest, election: election, position: 2, vote_method: :limited_choice, max_selections: 2, seats_count: 2)
      president_candidates = create_list(:election_candidate, 2, election_contest: president)
      vice_president_candidates = create_list(:election_candidate, 3, election_contest: vice_president)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_candidate_tallies.pluck(:election_candidate_id)).to match_array(
        (president_candidates + vice_president_candidates).map(&:id)
      )
      expect(election_session.election_contest_tallies.pluck(:election_contest_id)).to match_array([ president.id, vice_president.id ])
    end

    it "starts limited choice contests when candidates meet max selections" do
      election = create(:election)
      contest = create(:election_contest, election: election, vote_method: :limited_choice, max_selections: 2, seats_count: 2)
      create_list(:election_candidate, 2, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
    end

    it "fails limited choice contests when candidates are fewer than max selections" do
      election = create(:election)
      contest = create(:election_contest, election: election, vote_method: :limited_choice, max_selections: 2, seats_count: 2)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보자가 부족한 항목")
    end

    it "starts yes no contests with one candidate" do
      election = create(:election)
      contest = create(:election_contest, election: election, vote_method: :yes_no)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
    end

    it "starts approval contests with one candidate" do
      election = create(:election)
      contest = create(:election_contest, election: election, vote_method: :approval)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
    end

    it "fails without an actor" do
      election_session = create_ready_session

      result = described_class.new(election_session: election_session, actor: nil).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
    end

    it "fails when session is already in progress" do
      election_session = create_ready_session(status: :in_progress)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("준비 중인 선거 세션")
    end

    it "fails when session is closed" do
      election_session = create_ready_session(status: :closed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
    end

    it "fails when session is stopped" do
      election_session = create_ready_session(status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
    end

    it "fails for pin login sessions" do
      election_session = create_ready_session(operation_mode: :pin_login)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
    end

    it "fails when there are no contests" do
      election_session = create_startable_session

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("선거 항목이 없습니다.")
    end

    it "fails when a contest has no candidates" do
      election = create(:election)
      create(:election_contest, election: election)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보자가 부족한 항목")
    end

    it "fails single choice contests when candidates are fewer than max selections" do
      election = create(:election)
      contest = create(:election_contest, election: election, max_selections: 2, seats_count: 2)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보자가 부족한 항목")
    end

    it "fails when participant group has no participant slots" do
      election_session = create_ready_session(with_participant_slot: false)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 대상 학생이 없습니다.")
    end

    it "fails when election voters already exist" do
      election_session = create_ready_session
      create(:election_voter, election_session: election_session, teacher: election_session.teacher, participant_group: election_session.participant_group)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 생성된 진행 데이터")
    end

    it "fails when election progress already exists" do
      election_session = create_ready_session
      create(:election_progress, election_session: election_session)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 생성된 진행 데이터")
    end

    it "fails when tallies already exist" do
      election = create(:election)
      contest = create(:election_contest, election: election)
      candidate = create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)
      create(:participant_slot, participant_group: election_session.participant_group)
      create(:election_candidate_tally, election_session: election_session, election_contest: contest, election_candidate: candidate)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 생성된 진행 데이터")
    end

    it "does not leave partial data when start fails" do
      election = create(:election)
      contest = create(:election_contest, election: election, max_selections: 2, seats_count: 2)
      create(:election_candidate, election_contest: contest)
      election_session = create_startable_session(election: election)
      create(:participant_slot, participant_group: election_session.participant_group)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(election_session.reload).to be_draft
      expect(election_session.election_voters).to be_empty
      expect(election_session.election_participations).to be_empty
      expect(election_session.election_progress).to be_nil
      expect(election_session.election_candidate_tallies).to be_empty
      expect(election_session.election_contest_tallies).to be_empty
      expect(election_session.election_events).to be_empty
    end
  end

  def create_ready_session(status: :draft, operation_mode: :supervised, with_participant_slot: true)
    election = create(:election)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest)
    create_startable_session(election: election, status: status, operation_mode: operation_mode, with_participant_slot: with_participant_slot)
  end

  def create_startable_session(election: create(:election), status: :draft, operation_mode: :supervised, with_participant_slot: true)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group) if with_participant_slot
    create(:election_session, election: election, teacher: teacher, participant_group: participant_group, status: status, operation_mode: operation_mode)
  end

  def admin_overview_broadcasts_for(election)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election, :admin_overview ])).map { |broadcast| decoded_broadcast(broadcast) }
  end

  def decoded_broadcast(broadcast)
    JSON.parse(broadcast)
  rescue JSON::ParserError, TypeError
    broadcast
  end
end
