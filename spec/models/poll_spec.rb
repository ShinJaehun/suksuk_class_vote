require "rails_helper"

RSpec.describe Poll, type: :model do
  describe "factory" do
    it "builds a valid election" do
      election = build(:poll)

      expect(election).to be_valid
    end
  end

  describe "validations" do
    it "requires a title" do
      election = build(:poll, title: nil)

      expect(election).not_to be_valid
      expect(election.errors[:title]).to be_present
    end

    it "requires a user" do
      participant_group = create(:participant_group, :with_participant_slot)
      election = build(:poll, user: nil, participant_group: participant_group)

      expect(election).not_to be_valid
      expect(election.errors[:user]).to be_present
    end

    it "requires a participant group" do
      election = build(:poll, participant_group: nil)

      expect(election).not_to be_valid
      expect(election.errors[:participant_group]).to be_present
    end

    it "allows a closed election without a participant group" do
      election = build(:poll, status: :closed, participant_group: nil)

      expect(election).to be_valid
    end

    it "does not allow an empty participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      election = build(:poll, user: teacher, participant_group: participant_group)

      expect(election).not_to be_valid
      expect(election.errors[:participant_group]).to be_present
    end

    it "allows a participant group with participant slots" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      election = build(:poll, user: teacher, participant_group: participant_group)

      expect(election).to be_valid
    end
  end

  describe "status" do
    it "defaults to draft" do
      election = Poll.new

      expect(election).to be_draft
    end

    it "supports in progress and closed statuses" do
      election = build(:poll, status: :in_progress)

      expect(election).to be_in_progress
      expect(Poll.statuses).to include("closed" => 20)
    end
  end

  describe "kind" do
    it "defaults to election" do
      election = Poll.new

      expect(election).to be_election
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
    it "returns election labels" do
      election = build(:poll)

      expect(election.activity_label).to eq("선거")
      expect(election.choice_label).to eq("후보자")
      expect(election.choice_list_label).to eq("후보자")
      expect(election.choice_number_label).to eq("기호")
      expect(election.winner_label).to eq("최다 득표 후보")
      expect(election.vote_count_label).to eq("득표수")
    end

    it "returns discussion labels" do
      election = build(:poll, :discussion)

      expect(election.activity_label).to eq("토의")
      expect(election.choice_label).to eq("의견")
      expect(election.choice_list_label).to eq("의견")
      expect(election.choice_number_label).to eq("번호")
      expect(election.winner_label).to eq("가장 많이 선택된 의견")
      expect(election.vote_count_label).to eq("선택 수")
    end

    it "returns debate labels" do
      election = build(:poll, :debate)

      expect(election.activity_label).to eq("토론")
      expect(election.choice_label).to eq("입장")
      expect(election.choice_list_label).to eq("입장")
      expect(election.choice_number_label).to eq("번호")
      expect(election.winner_label).to eq("가장 많이 선택된 입장")
      expect(election.vote_count_label).to eq("선택 수")
    end
  end
end
