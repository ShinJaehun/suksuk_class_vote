require "rails_helper"

RSpec.describe PollContest, type: :model do
  describe "factory" do
    it "builds a valid poll_contest" do
      poll_contest = build(:poll_contest)

      expect(poll_contest).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_contest = build(:poll_contest, poll: nil)

      expect(poll_contest).not_to be_valid
      expect(poll_contest.errors[:poll]).to be_present
    end

    it "requires a title" do
      poll_contest = build(:poll_contest, title: nil)

      expect(poll_contest).not_to be_valid
      expect(poll_contest.errors[:title]).to be_present
    end

    it "requires a positive integer position" do
      poll_contest = build(:poll_contest, position: 0)

      expect(poll_contest).not_to be_valid
      expect(poll_contest.errors[:position]).to be_present
    end

    it "does not allow duplicate positions in the same poll" do
      poll = create(:poll)
      poll_contest = build(:poll_contest, poll: poll, position: poll.default_poll_contest.position)

      expect(poll_contest).not_to be_valid
      expect(poll_contest.errors[:position]).to be_present
    end
  end

  describe "school election source" do
    it "is optional" do
      poll_contest = build(:poll_contest, school_election_contest: nil)

      expect(poll_contest).to be_valid
    end

    it "can reference a school election contest" do
      school_election_contest = create(:school_election_contest)
      poll_contest = create(:poll_contest, school_election_contest: school_election_contest)

      expect(poll_contest.school_election_contest).to eq(school_election_contest)
    end
  end
end
