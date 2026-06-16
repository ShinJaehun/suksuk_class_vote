require "rails_helper"

RSpec.describe PollOption, type: :model do
  describe "factory" do
    it "builds a valid poll_option" do
      poll_option = build(:poll_option)

      expect(poll_option).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_option = build(:poll_option, poll: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll]).to be_present
    end

    it "requires a poll_contest" do
      poll_option = build(:poll_option, poll_contest: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll_contest]).to be_present
    end

    it "requires a number" do
      poll_option = build(:poll_option, number: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      poll_option = build(:poll_option, number: 0)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "requires a name" do
      poll_option = build(:poll_option, name: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same poll contest" do
      poll = create(:poll)
      create(:poll_option, poll: poll, number: 1)
      poll_option = build(:poll_option, poll: poll, number: 1)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "allows the same number in different poll contests" do
      poll = create(:poll)
      another_poll_contest = create(:poll_contest, poll: poll)
      create(:poll_option, poll: poll, number: 1)
      poll_option = build(:poll_option, poll: poll, poll_contest: another_poll_contest, number: 1)

      expect(poll_option).to be_valid
    end

    it "allows the same number in different polls" do
      create(:poll_option, number: 1)
      poll_option = build(:poll_option, number: 1)

      expect(poll_option).to be_valid
    end

    it "requires the poll_contest to belong to the poll" do
      poll = create(:poll)
      poll_contest = create(:poll_contest)
      poll_option = build(:poll_option, poll: poll, poll_contest: poll_contest)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll_contest]).to be_present
    end
  end
end
