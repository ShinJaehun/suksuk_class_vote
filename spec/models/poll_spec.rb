require "rails_helper"

RSpec.describe Poll, type: :model do
  describe "factory" do
    it "builds a valid poll" do
      poll = build(:poll)

      expect(poll).to be_valid
    end
  end

  describe "validations" do
    it "requires a title" do
      poll = build(:poll, title: nil)

      expect(poll).not_to be_valid
      expect(poll.errors[:title]).to be_present
    end

    it "requires a user" do
      participant_group = create(:participant_group, :with_participant_slot)
      poll = build(:poll, user: nil, participant_group: participant_group)

      expect(poll).not_to be_valid
      expect(poll.errors[:user]).to be_present
    end

    it "requires a participant group" do
      poll = build(:poll, participant_group: nil)

      expect(poll).not_to be_valid
      expect(poll.errors[:participant_group]).to be_present
    end

    it "allows a closed poll without a participant group" do
      poll = build(:poll, status: :closed, participant_group: nil)

      expect(poll).to be_valid
    end

    it "does not allow an empty participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      poll = build(:poll, user: teacher, participant_group: participant_group)

      expect(poll).not_to be_valid
      expect(poll.errors[:participant_group]).to be_present
    end

    it "allows a participant group with participant slots" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      poll = build(:poll, user: teacher, participant_group: participant_group)

      expect(poll).to be_valid
    end
  end

  describe "poll contests" do
    it "creates a default poll contest when a poll is created" do
      poll = create(:poll)

      expect(poll.default_poll_contest).to have_attributes(
        title: "기본",
        position: 1
      )
    end
  end

  describe "#school_election_poll?" do
    it "returns false for a regular poll" do
      poll = create(:poll)

      expect(poll).not_to be_school_election_poll
    end

    it "returns true when linked to a school election classroom session" do
      poll = create(:poll)
      create(
        :school_election_classroom_session,
        teacher: poll.user,
        participant_group: poll.participant_group,
        poll: poll
      )

      expect(poll.reload).to be_school_election_poll
    end
  end

  describe "status" do
    it "defaults to draft" do
      poll = Poll.new

      expect(poll).to be_draft
    end

    it "supports in progress, closed, and stopped statuses" do
      poll = build(:poll, status: :in_progress)

      expect(poll).to be_in_progress
      expect(Poll.statuses).to include("closed" => 20, "stopped" => 30)
    end

    it "allows a stopped poll without a participant group" do
      poll = build(:poll, status: :stopped, participant_group: nil)

      expect(poll).to be_valid
    end
  end

  describe "kind" do
    it "defaults to poll" do
      poll = Poll.new

      expect(poll).to be_election
    end

    it "supports discussion and debate kinds" do
      discussion = build(:poll, :discussion)
      debate = build(:poll, :debate)

      expect(discussion).to be_discussion
      expect(debate).to be_debate
      expect(Poll.kinds).to include("discussion" => 10, "debate" => 20)
    end
  end

  describe "display labels" do
    it "returns poll labels" do
      poll = build(:poll)

      expect(poll.activity_label).to eq("선거")
      expect(poll.choice_label).to eq("후보자")
      expect(poll.choice_list_label).to eq("후보자")
      expect(poll.choice_number_label).to eq("기호")
      expect(poll.winner_label).to eq("최다 득표 후보")
      expect(poll.vote_count_label).to eq("득표수")
    end

    it "returns discussion labels" do
      poll = build(:poll, :discussion)

      expect(poll.activity_label).to eq("토의")
      expect(poll.choice_label).to eq("의견")
      expect(poll.choice_list_label).to eq("의견")
      expect(poll.choice_number_label).to eq("번호")
      expect(poll.winner_label).to eq("가장 많이 선택된 의견")
      expect(poll.vote_count_label).to eq("선택 수")
    end

    it "returns debate labels" do
      poll = build(:poll, :debate)

      expect(poll.activity_label).to eq("토론")
      expect(poll.choice_label).to eq("입장")
      expect(poll.choice_list_label).to eq("입장")
      expect(poll.choice_number_label).to eq("번호")
      expect(poll.winner_label).to eq("가장 많이 선택된 입장")
      expect(poll.vote_count_label).to eq("선택 수")
    end
  end

  describe "destroy policy" do
    it "allows draft, stopped, and unarchived closed polls to be destroyed" do
      draft_poll = create(:poll)
      stopped_poll = create(:poll, status: :stopped)
      closed_poll = create(:poll, status: :closed)

      expect(draft_poll.destroy).to be_truthy
      expect(stopped_poll.destroy).to be_truthy
      expect(closed_poll.destroy).to be_truthy
    end

    it "blocks in progress and archived closed polls from being destroyed" do
      in_progress_poll = create(:poll, status: :in_progress)
      archived_closed_poll = create(:poll, status: :closed, archived_at: Time.current)

      expect(in_progress_poll.destroy).to be_falsey
      expect(archived_closed_poll.destroy).to be_falsey
      expect(in_progress_poll.errors[:base]).to include("진행 중이거나 보관된 투표는 삭제할 수 없습니다.")
      expect(archived_closed_poll.errors[:base]).to include("진행 중이거나 보관된 투표는 삭제할 수 없습니다.")
    end
  end
end
