require "rails_helper"

RSpec.describe "PollSession execution links", type: :model do
  let(:school) { create(:school) }
  let(:poll) { create(:poll, school: school) }

  def create_poll_session_for(poll)
    classroom = create(:classroom, :with_teacher, school: poll.school)
    create(:poll_session, poll: poll, classroom: classroom, operator: classroom.teacher)
  end

  describe "PollSession associations" do
    it "requires runtime records to belong to a PollSession" do
      expect(build(:poll_progress, poll: poll, poll_session: nil)).to be_invalid
      expect(build(:poll_option_tally, poll: poll, poll_session: nil)).to be_invalid
      expect(build(:poll_contest_tally, poll: poll, poll_session: nil)).to be_invalid
      expect(build(:poll_event, poll: poll)).to be_valid
    end

    it "accepts records linked to a PollSession for the same Poll" do
      poll_session = create_poll_session_for(poll)
      poll_option = create(:poll_option, poll: poll)
      poll_contest = poll_option.poll_contest

      expect(build(:poll_participant, poll: poll, poll_session: poll_session)).to be_valid
      expect(build(:poll_progress, poll: poll, poll_session: poll_session)).to be_valid
      expect(build(:poll_option_tally, poll: poll, poll_session: poll_session,
                                       poll_option: poll_option)).to be_valid
      expect(build(:poll_contest_tally, poll: poll, poll_session: poll_session,
                                        poll_contest: poll_contest)).to be_valid
      expect(build(:poll_event, poll: poll, poll_session: poll_session)).to be_valid
    end

    it "rejects records linked to a PollSession for another Poll" do
      poll_session = create_poll_session_for(poll)
      other_poll = create(:poll, school: school)
      poll_option = create(:poll_option, poll: other_poll)
      poll_contest = poll_option.poll_contest

      records = [
        build(:poll_participant, poll: other_poll, poll_session: poll_session),
        build(:poll_progress, poll: other_poll, poll_session: poll_session),
        build(:poll_option_tally, poll: other_poll, poll_session: poll_session,
                                  poll_option: poll_option),
        build(:poll_contest_tally, poll: other_poll, poll_session: poll_session,
                                   poll_contest: poll_contest),
        build(:poll_event, poll: other_poll, poll_session: poll_session)
      ]

      records.each do |record|
        expect(record).to be_invalid
        expect(record.errors[:poll_session]).to be_present
      end
    end
  end

  describe "PollSession record access" do
    it "exposes its execution records" do
      poll_session = create_poll_session_for(poll)
      poll_option = create(:poll_option, poll: poll)
      participant = create(:poll_participant, poll: poll, poll_session: poll_session)
      progress = create(:poll_progress, poll: poll, poll_session: poll_session)
      option_tally = create(:poll_option_tally, poll: poll, poll_session: poll_session,
                                                poll_option: poll_option)
      contest_tally = create(:poll_contest_tally, poll: poll, poll_session: poll_session,
                                                  poll_contest: poll_option.poll_contest)
      event = create(:poll_event, poll: poll, poll_session: poll_session)

      expect(poll_session.poll_participants).to contain_exactly(participant)
      expect(poll_session.poll_progress).to eq(progress)
      expect(poll_session.poll_option_tallies).to contain_exactly(option_tally)
      expect(poll_session.poll_contest_tallies).to contain_exactly(contest_tally)
      expect(poll_session.poll_events).to contain_exactly(event)
    end
  end

  describe "runtime uniqueness" do
    it "keeps participant numbers unique per PollSession" do
      first_session = create_poll_session_for(poll)
      second_session = create_poll_session_for(poll)
      create(:poll_participant, poll: poll, poll_session: first_session, number: 2)

      expect(build(:poll_participant, poll: poll, poll_session: first_session, number: 2)).to be_invalid
      expect(build(:poll_participant, poll: poll, poll_session: second_session, number: 2)).to be_valid
    end

    it "keeps progress unique per PollSession" do
      first_session = create_poll_session_for(poll)
      second_session = create_poll_session_for(poll)
      create(:poll_progress, poll: poll, poll_session: first_session)

      expect(build(:poll_progress, poll: poll, poll_session: first_session)).to be_invalid
      expect(build(:poll_progress, poll: poll, poll_session: second_session)).to be_valid
    end

    it "keeps option tallies unique per PollSession" do
      poll_option = create(:poll_option, poll: poll)
      first_session = create_poll_session_for(poll)
      second_session = create_poll_session_for(poll)
      create(:poll_option_tally, poll: poll, poll_session: first_session, poll_option: poll_option)

      expect(build(:poll_option_tally, poll: poll, poll_session: first_session,
                                       poll_option: poll_option)).to be_invalid
      expect(build(:poll_option_tally, poll: poll, poll_session: second_session,
                                       poll_option: poll_option)).to be_valid
    end

    it "keeps contest tallies unique per PollSession" do
      poll_contest = poll.default_poll_contest
      first_session = create_poll_session_for(poll)
      second_session = create_poll_session_for(poll)
      create(:poll_contest_tally, poll: poll, poll_session: first_session,
                                  poll_contest: poll_contest)

      expect(build(:poll_contest_tally, poll: poll, poll_session: first_session,
                                        poll_contest: poll_contest)).to be_invalid
      expect(build(:poll_contest_tally, poll: poll, poll_session: second_session,
                                        poll_contest: poll_contest)).to be_valid
    end

    it "allows multiple events in the same PollSession" do
      poll_session = create_poll_session_for(poll)

      expect do
        create(:poll_event, poll: poll, poll_session: poll_session)
        create(:poll_event, poll: poll, poll_session: poll_session)
      end.to change(PollEvent, :count).by(2)
    end
  end

  describe "deletion restriction" do
    it "prevents deletion of a PollSession with execution records" do
      poll_session = create_poll_session_for(poll)
      create(:poll_participant, poll: poll, poll_session: poll_session)

      expect(poll_session.destroy).to be(false)
    end
  end
end
