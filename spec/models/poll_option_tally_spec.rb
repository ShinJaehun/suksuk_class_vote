require "rails_helper"

RSpec.describe PollOptionTally, type: :model do
  describe "factory" do
    it "builds a valid poll_option tally" do
      poll_option_tally = build(:poll_option_tally)

      expect(poll_option_tally).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_option_tally = build(:poll_option_tally, poll: nil)

      expect(poll_option_tally).not_to be_valid
      expect(poll_option_tally.errors[:poll]).to be_present
    end

    it "requires a poll_option" do
      poll_option_tally = build(:poll_option_tally, poll: create(:poll), poll_option: nil)

      expect(poll_option_tally).not_to be_valid
      expect(poll_option_tally.errors[:poll_option]).to be_present
    end

    it "requires one tally per poll and poll_option" do
      poll_option = create(:poll_option)
      create(:poll_option_tally, poll: poll_option.poll, poll_option: poll_option)
      poll_option_tally = build(:poll_option_tally, poll: poll_option.poll, poll_option: poll_option)

      expect(poll_option_tally).not_to be_valid
      expect(poll_option_tally.errors[:poll_option_id]).to be_present
    end

    it "allows poll-level and session tallies for the same option to coexist" do
      poll_option = create(:poll_option)
      poll = poll_option.poll
      school = create(:school)
      poll.update!(school: school, participant_group: nil)
      classroom = create(:classroom, school: school)

      operator = create(:user)
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator
      )

      create(:poll_option_tally, poll: poll, poll_option: poll_option)

      session_tally = build(
        :poll_option_tally,
        poll: poll,
        poll_session: poll_session,
        poll_option: poll_option
      )

      expect(session_tally).to be_valid
    end

    it "rejects duplicate option tallies within one session" do
      poll_option = create(:poll_option)
      poll = poll_option.poll
      school = create(:school)
      poll.update!(school: school, participant_group: nil)
      classroom = create(:classroom, school: school)

      operator = create(:user)
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator
      )

      create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: poll_option)

      duplicate = build(
        :poll_option_tally,
        poll: poll,
        poll_session: poll_session,
        poll_option: poll_option
      )

      expect(duplicate).not_to be_valid
    end

    it "allows the same option tally in different sessions" do
      poll_option = create(:poll_option)
      poll = poll_option.poll
      school = create(:school)
      poll.update!(school: school, participant_group: nil)

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

      create(:poll_option_tally, poll: poll, poll_session: first_session, poll_option: poll_option)

      second_tally = build(
        :poll_option_tally,
        poll: poll,
        poll_session: second_session,
        poll_option: poll_option
      )

      expect(second_tally).to be_valid
    end

    it "does not allow negative votes count" do
      poll_option_tally = build(:poll_option_tally, votes_count: -1)

      expect(poll_option_tally).not_to be_valid
      expect(poll_option_tally.errors[:votes_count]).to be_present
    end

    it "requires the poll_option to belong to the poll" do
      poll = create(:poll)
      poll_option = create(:poll_option)
      poll_option_tally = build(:poll_option_tally, poll: poll, poll_option: poll_option)

      expect(poll_option_tally).not_to be_valid
      expect(poll_option_tally.errors[:poll_option]).to be_present
    end
  end
end
