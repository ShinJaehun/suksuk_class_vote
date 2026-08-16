require "rails_helper"

RSpec.describe PollContestTally, type: :model do
  describe "factory" do
    it "builds a valid poll contest tally" do
      poll_contest_tally = build(:poll_contest_tally)

      expect(poll_contest_tally).to be_valid
    end
  end

  describe "associations" do
    it "is available from poll" do
      poll_contest_tally = create(:poll_contest_tally)

      expect(poll_contest_tally.poll.poll_contest_tallies).to include(poll_contest_tally)
    end

    it "is available from poll contest" do
      poll_contest_tally = create(:poll_contest_tally)

      expect(poll_contest_tally.poll_contest.poll_contest_tally).to eq(poll_contest_tally)
    end

    it "is destroyed with poll" do
      poll_contest_tally = create(:poll_contest_tally)
      poll = poll_contest_tally.poll

      expect do
        poll.destroy!
      end.to change(described_class, :count).by(-1)
    end

    it "is destroyed with poll contest" do
      poll_contest_tally = create(:poll_contest_tally)
      poll_contest = poll_contest_tally.poll_contest

      expect do
        poll_contest.destroy!
      end.to change(described_class, :count).by(-1)
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_contest_tally = build(:poll_contest_tally, poll: nil)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:poll]).to be_present
    end

    it "requires a poll contest" do
      poll_contest_tally = build(:poll_contest_tally, poll: create(:poll), poll_contest: nil)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:poll_contest]).to be_present
    end

    it "defaults abstentions count to 0" do
      poll_contest = create(:poll_contest)
      poll_contest_tally = described_class.create!(
        poll_contest: poll_contest,
        poll: poll_contest.poll
      )

      expect(poll_contest_tally.abstentions_count).to eq(0)
    end

    it "does not allow negative abstentions count" do
      poll_contest_tally = build(:poll_contest_tally, abstentions_count: -1)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:abstentions_count]).to be_present
    end

    it "requires integer abstentions count" do
      poll_contest_tally = build(:poll_contest_tally, abstentions_count: 1.5)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:abstentions_count]).to be_present
    end

    it "does not allow duplicate tallies for the same poll and poll contest" do
      poll_contest = create(:poll_contest)
      create(:poll_contest_tally, poll: poll_contest.poll, poll_contest: poll_contest)
      poll_contest_tally = build(:poll_contest_tally, poll: poll_contest.poll, poll_contest: poll_contest)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:poll_contest_id]).to be_present
    end

    it "allows poll-level and session tallies for the same contest to coexist" do
      poll_contest = create(:poll_contest)
      poll = poll_contest.poll
      school = create(:school)
      poll.update!(school: school)

      operator = create(:user)
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: operator
      )

      create(:poll_contest_tally, poll: poll, poll_contest: poll_contest)

      session_tally = build(
        :poll_contest_tally,
        poll: poll,
        poll_session: poll_session,
        poll_contest: poll_contest
      )

      expect(session_tally).to be_valid
    end

    it "rejects duplicate contest tallies within one session" do
      poll_contest = create(:poll_contest)
      poll = poll_contest.poll
      school = create(:school)
      poll.update!(school: school)

      operator = create(:user)
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: operator
      )

      create(:poll_contest_tally, poll: poll, poll_session: poll_session, poll_contest: poll_contest)

      duplicate = build(
        :poll_contest_tally,
        poll: poll,
        poll_session: poll_session,
        poll_contest: poll_contest
      )

      expect(duplicate).not_to be_valid
    end

    it "allows the same contest tally in different sessions" do
      poll_contest = create(:poll_contest)
      poll = poll_contest.poll
      school = create(:school)
      poll.update!(school: school)

      operator = create(:user)
      first_session = create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: operator
      )
      second_session = create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: operator
      )

      create(:poll_contest_tally, poll: poll, poll_session: first_session, poll_contest: poll_contest)

      second_tally = build(
        :poll_contest_tally,
        poll: poll,
        poll_session: second_session,
        poll_contest: poll_contest
      )

      expect(second_tally).to be_valid
    end

    it "allows tallies for different poll contests in the same poll" do
      poll = create(:poll)
      create(:poll_contest_tally, poll: poll, poll_contest: poll.default_poll_contest)
      poll_contest = create(:poll_contest, poll: poll, position: 2)
      poll_contest_tally = build(:poll_contest_tally, poll: poll, poll_contest: poll_contest)

      expect(poll_contest_tally).to be_valid
    end

    it "requires the poll contest to belong to the poll" do
      poll = create(:poll)
      poll_contest = create(:poll_contest)
      poll_contest_tally = build(:poll_contest_tally, poll: poll, poll_contest: poll_contest)

      expect(poll_contest_tally).not_to be_valid
      expect(poll_contest_tally.errors[:poll_contest]).to be_present
    end
  end
end
