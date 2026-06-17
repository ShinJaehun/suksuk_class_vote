require "rails_helper"

RSpec.describe SchoolElectionCandidate, type: :model do
  describe "factory" do
    it "builds a valid school election candidate" do
      candidate = build(:school_election_candidate)

      expect(candidate).to be_valid
    end
  end

  describe "validations" do
    it "requires a school election contest" do
      candidate = build(:school_election_candidate, school_election_contest: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:school_election_contest]).to be_present
    end

    it "requires a number" do
      candidate = build(:school_election_candidate, number: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      candidate = build(:school_election_candidate, number: 0)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "does not allow duplicate numbers in the same contest" do
      contest = create(:school_election_contest)
      create(:school_election_candidate, school_election_contest: contest, number: 1)
      candidate = build(:school_election_candidate, school_election_contest: contest, number: 1)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "allows the same number in different contests" do
      create(:school_election_candidate, number: 1)
      candidate = build(:school_election_candidate, number: 1)

      expect(candidate).to be_valid
    end

    it "requires a name" do
      candidate = build(:school_election_candidate, name: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:name]).to be_present
    end

    it "requires a grade class label" do
      candidate = build(:school_election_candidate, grade_class_label: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:grade_class_label]).to be_present
    end
  end

  describe "associations" do
    it "can find linked poll options" do
      candidate = create(:school_election_candidate)
      poll_option = create(:poll_option, school_election_candidate: candidate)

      expect(candidate.poll_options).to contain_exactly(poll_option)
    end
  end
end
