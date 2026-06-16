require "rails_helper"

RSpec.describe Polls::Start do
  describe "#call" do
    it "starts a draft poll with at least two poll_options, snapshots participant slots, creates tallies, and creates a poll progress" do
      poll = create_startable_poll
      first_slot = poll.participant_group.participant_slots.order(:number).first

      result = described_class.new(poll).call

      expect(result).to be_success
      expect(poll.reload).to be_in_progress
      expect(poll.participant_group_name_snapshot).to eq(poll.participant_group.name)
      expect(poll.poll_participants.count).to eq(2)
      expect(poll.poll_participants.order(:number).first).to have_attributes(
        source_participant_slot: first_slot,
        number: first_slot.number,
        name: first_slot.name
      )
      expect(poll.poll_option_tallies.count).to eq(2)
      expect(poll.poll_option_tallies.order(:poll_option_id)).to all(have_attributes(
        poll: poll,
        votes_count: 0
      ))
      expect(poll.poll_option_tallies.map(&:poll_option)).to match_array(poll.poll_options)
      expect(poll.poll_progress).to have_attributes(
        current_poll_participant: poll.poll_participants.order(:number).first,
        status: "active",
        ballot_status: "ballot_locked"
      )
      expect(poll.poll_progress.started_at).to be_present
      expect(poll.poll_events.last).to have_attributes(
        event_type: "poll_started",
        poll_participant: poll.poll_participants.order(:number).first
      )
      expect(poll.poll_events.last.details).to include(
        "voter_count" => 2,
        "poll_option_count" => 2
      )
    end

    it "records the actor when provided" do
      poll = create_startable_poll
      actor = poll.user

      result = described_class.new(poll, actor: actor).call

      expect(result).to be_success
      expect(poll.poll_events.last.actor).to eq(actor)
    end

    it "preserves participant slot values from the start moment" do
      poll = create_startable_poll
      participant_slot = poll.participant_group.participant_slots.order(:number).first

      described_class.new(poll).call
      participant_slot.update!(name: "변경된 이름")

      expect(poll.poll_participants.order(:number).first.name).not_to eq("변경된 이름")
    end

    it "fails when the poll is not draft" do
      poll = create_startable_poll(status: :in_progress)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("draft 상태")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_nil
    end

    it "fails when there are no poll_options" do
      poll = create(:poll)

      expect do
        result = described_class.new(poll).call

        expect(result).not_to be_success
        expect(result.error_message).to include("후보자가 2명 이상")
      end.not_to change(PollOptionTally, :count)

      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
    end

    it "fails with a policy message when there is one poll_option" do
      poll = create(:poll)
      create(:poll_option, poll: poll)

      expect do
        result = described_class.new(poll).call

        expect(result).not_to be_success
        expect(result.error_message).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      end.not_to change(PollOptionTally, :count)

      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
    end

    it "fails when participant slots are empty" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      poll = build(:poll, user: teacher, participant_group: participant_group)
      poll.save!(validate: false)
      create(:poll_option, poll: poll, number: 1)
      create(:poll_option, poll: poll, number: 2)

      expect do
        result = described_class.new(poll).call

        expect(result).not_to be_success
        expect(result.error_message).to include("투표자 명단이 1명 이상")
      end.not_to change(PollOptionTally, :count)

      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
    end

    it "fails when the snapshot already exists" do
      poll = create_startable_poll
      participant_slot = poll.participant_group.participant_slots.order(:number).first
      create(:poll_participant, poll: poll, source_participant_slot: participant_slot, number: participant_slot.number)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표자 명단")
      expect(poll.reload).to be_draft
      expect(poll.poll_participants.count).to eq(1)
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_nil
    end

    it "fails when the poll progress already exists" do
      poll = create_startable_poll
      create(:poll_progress, poll: poll)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 진행 정보")
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_present
    end

    it "fails when poll_option tallies already exist" do
      poll = create_startable_poll
      poll_option = poll.poll_options.order(:number).first
      create(:poll_option_tally, poll: poll, poll_option: poll_option)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 후보별 집계 정보")
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies.count).to eq(1)
      expect(poll.poll_progress).to be_nil
    end

    it "rolls back status when snapshot creation fails" do
      poll = create_startable_poll
      poll.participant_group.participant_slots.order(:number).first.update_column(:name, "")

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_nil
    end

    it "rolls back snapshot and status when poll_option tally creation fails" do
      poll = create_startable_poll
      allow(poll.poll_option_tallies).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_nil
    end

    it "rolls back snapshot and status when poll progress creation fails" do
      poll = create_startable_poll
      allow(poll).to receive(:create_poll_progress!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll).call

      expect(result).not_to be_success
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
      expect(poll.poll_option_tallies).to be_empty
      expect(poll.poll_progress).to be_nil
    end
  end

  def create_startable_poll(status: :draft)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    poll = create(:poll, user: teacher, participant_group: participant_group, status: status)
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    poll
  end
end
