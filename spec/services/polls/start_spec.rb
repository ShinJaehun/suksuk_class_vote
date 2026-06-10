require "rails_helper"

RSpec.describe Polls::Start do
  describe "#call" do
    it "starts a draft election with at least two poll_options, snapshots participant slots, creates tallies, and creates a poll progress" do
      election = create_startable_election
      first_slot = election.participant_group.participant_slots.order(:number).first

      result = described_class.new(election).call

      expect(result).to be_success
      expect(election.reload).to be_in_progress
      expect(election.participant_group_name_snapshot).to eq(election.participant_group.name)
      expect(election.poll_participants.count).to eq(2)
      expect(election.poll_participants.order(:number).first).to have_attributes(
        source_participant_slot: first_slot,
        number: first_slot.number,
        name: first_slot.name
      )
      expect(election.poll_option_tallies.count).to eq(2)
      expect(election.poll_option_tallies.order(:poll_option_id)).to all(have_attributes(
        poll: election,
        votes_count: 0
      ))
      expect(election.poll_option_tallies.map(&:poll_option)).to match_array(election.poll_options)
      expect(election.poll_progress).to have_attributes(
        current_poll_participant: election.poll_participants.order(:number).first,
        status: "active"
      )
      expect(election.poll_progress.started_at).to be_present
      expect(election.poll_events.last).to have_attributes(
        event_type: "poll_started",
        poll_participant: election.poll_participants.order(:number).first
      )
      expect(election.poll_events.last.details).to include(
        "voter_count" => 2,
        "poll_option_count" => 2
      )
    end

    it "records the actor when provided" do
      election = create_startable_election
      actor = election.user

      result = described_class.new(election, actor: actor).call

      expect(result).to be_success
      expect(election.poll_events.last.actor).to eq(actor)
    end

    it "preserves participant slot values from the start moment" do
      election = create_startable_election
      participant_slot = election.participant_group.participant_slots.order(:number).first

      described_class.new(election).call
      participant_slot.update!(name: "변경된 이름")

      expect(election.poll_participants.order(:number).first.name).not_to eq("변경된 이름")
    end

    it "fails when the election is not draft" do
      election = create_startable_election(status: :in_progress)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("draft 상태")
      expect(election.reload).to be_in_progress
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_nil
    end

    it "fails when there are no poll_options" do
      election = create(:poll)

      expect do
        result = described_class.new(election).call

        expect(result).not_to be_success
        expect(result.error_message).to include("후보자가 2명 이상")
      end.not_to change(PollOptionTally, :count)

      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
    end

    it "fails with a policy message when there is one poll_option" do
      election = create(:poll)
      create(:poll_option, poll: election)

      expect do
        result = described_class.new(election).call

        expect(result).not_to be_success
        expect(result.error_message).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      end.not_to change(PollOptionTally, :count)

      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
    end

    it "fails when participant slots are empty" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      election = build(:poll, user: teacher, participant_group: participant_group)
      election.save!(validate: false)
      create(:poll_option, poll: election, number: 1)
      create(:poll_option, poll: election, number: 2)

      expect do
        result = described_class.new(election).call

        expect(result).not_to be_success
        expect(result.error_message).to include("참여자 명단이 1명 이상")
      end.not_to change(PollOptionTally, :count)

      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
    end

    it "fails when the snapshot already exists" do
      election = create_startable_election
      participant_slot = election.participant_group.participant_slots.order(:number).first
      create(:poll_participant, poll: election, source_participant_slot: participant_slot, number: participant_slot.number)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 참여자 명단")
      expect(election.reload).to be_draft
      expect(election.poll_participants.count).to eq(1)
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_nil
    end

    it "fails when the poll progress already exists" do
      election = create_startable_election
      create(:poll_progress, poll: election)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 진행 정보")
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_present
    end

    it "fails when poll_option tallies already exist" do
      election = create_startable_election
      poll_option = election.poll_options.order(:number).first
      create(:poll_option_tally, poll: election, poll_option: poll_option)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 후보별 집계 정보")
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies.count).to eq(1)
      expect(election.poll_progress).to be_nil
    end

    it "rolls back status when snapshot creation fails" do
      election = create_startable_election
      election.participant_group.participant_slots.order(:number).first.update_column(:name, "")

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_nil
    end

    it "rolls back snapshot and status when poll_option tally creation fails" do
      election = create_startable_election
      allow(election.poll_option_tallies).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_nil
    end

    it "rolls back snapshot and status when poll progress creation fails" do
      election = create_startable_election
      allow(election).to receive(:create_poll_progress!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
      expect(election.poll_option_tallies).to be_empty
      expect(election.poll_progress).to be_nil
    end
  end

  def create_startable_election(status: :draft)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    election = create(:poll, user: teacher, participant_group: participant_group, status: status)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    election
  end
end
