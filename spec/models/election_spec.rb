require "rails_helper"

RSpec.describe Election, type: :model do
  describe "factory" do
    it "builds a valid election" do
      election = build(:election)

      expect(election).to be_valid
    end
  end

  describe "validations" do
    it "requires a title" do
      election = build(:election, title: nil)

      expect(election).not_to be_valid
      expect(election.errors[:title]).to be_present
    end

    it "requires a user" do
      voter_group = create(:voter_group, :with_voter_slot)
      election = build(:election, user: nil, voter_group: voter_group)

      expect(election).not_to be_valid
      expect(election.errors[:user]).to be_present
    end

    it "requires a voter group" do
      election = build(:election, voter_group: nil)

      expect(election).not_to be_valid
      expect(election.errors[:voter_group]).to be_present
    end

    it "allows a closed election without a voter group" do
      election = build(:election, status: :closed, voter_group: nil)

      expect(election).to be_valid
    end

    it "does not allow an empty voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      election = build(:election, user: teacher, voter_group: voter_group)

      expect(election).not_to be_valid
      expect(election.errors[:voter_group]).to be_present
    end

    it "allows a voter group with voter slots" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      election = build(:election, user: teacher, voter_group: voter_group)

      expect(election).to be_valid
    end
  end

  describe "status" do
    it "defaults to draft" do
      election = Election.new

      expect(election).to be_draft
    end

    it "supports in progress and closed statuses" do
      election = build(:election, status: :in_progress)

      expect(election).to be_in_progress
      expect(Election.statuses).to include("closed" => 20)
    end
  end

  describe "kind" do
    it "defaults to election" do
      election = Election.new

      expect(election).to be_election
    end

    it "supports discussion and debate kinds" do
      discussion = build(:election, :discussion)
      debate = build(:election, :debate)

      expect(discussion).to be_discussion
      expect(debate).to be_debate
      expect(Election.kinds).to include("discussion" => 10, "debate" => 20)
    end
  end

  describe "display labels" do
    it "returns election labels" do
      election = build(:election)

      expect(election.activity_label).to eq("선거")
      expect(election.choice_label).to eq("후보자")
      expect(election.choice_list_label).to eq("후보자")
      expect(election.choice_number_label).to eq("기호")
      expect(election.winner_label).to eq("최다 득표 후보")
      expect(election.vote_count_label).to eq("득표수")
    end

    it "returns discussion labels" do
      election = build(:election, :discussion)

      expect(election.activity_label).to eq("토의")
      expect(election.choice_label).to eq("의견")
      expect(election.choice_list_label).to eq("의견")
      expect(election.choice_number_label).to eq("번호")
      expect(election.winner_label).to eq("가장 많이 선택된 의견")
      expect(election.vote_count_label).to eq("선택 수")
    end

    it "returns debate labels" do
      election = build(:election, :debate)

      expect(election.activity_label).to eq("토론")
      expect(election.choice_label).to eq("입장")
      expect(election.choice_list_label).to eq("입장")
      expect(election.choice_number_label).to eq("번호")
      expect(election.winner_label).to eq("가장 많이 선택된 입장")
      expect(election.vote_count_label).to eq("선택 수")
    end
  end
end
