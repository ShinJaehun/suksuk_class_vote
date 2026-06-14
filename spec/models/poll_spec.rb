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
    it "allows draft and stopped polls to be destroyed" do
      draft_poll = create(:poll)
      stopped_poll = create(:poll, status: :stopped)

      expect(draft_poll.destroy).to be_truthy
      expect(stopped_poll.destroy).to be_truthy
    end

    it "blocks in progress and closed polls from being destroyed" do
      in_progress_poll = create(:poll, status: :in_progress)
      closed_poll = create(:poll, status: :closed)

      expect(in_progress_poll.destroy).to be_falsey
      expect(closed_poll.destroy).to be_falsey
      expect(in_progress_poll.errors[:base]).to include("진행 중이거나 종료된 투표는 삭제할 수 없습니다.")
      expect(closed_poll.errors[:base]).to include("진행 중이거나 종료된 투표는 삭제할 수 없습니다.")
    end
  end
end
