require "rails_helper"

RSpec.describe SchoolElections::CreateClassroomPoll do
  describe "#call" do
    it "creates a draft poll for the session" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result).to be_success
      expect(result.poll).to be_draft
      expect(result.poll.title).to eq("#{session.school_election.title} - #{session.participant_group.name}")
    end

    it "links the poll to the session" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(session.reload.poll).to eq(result.poll)
    end

    it "uses session teacher and participant group on the poll" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result.poll.user).to eq(session.teacher)
      expect(result.poll.participant_group).to eq(session.participant_group)
    end

    it "creates poll contests from school election contests in position order" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result.poll.poll_contests.order(:position).pluck(:title)).to eq(["회장", "6학년 부회장", "5학년 부회장"])
    end

    it "reuses and updates the default poll contest for the first school election contest" do
      session = create_session_with_sources

      result = described_class.new(session).call

      first_source_contest = session.school_election.school_election_contests.order(:position).first
      first_poll_contest = result.poll.poll_contests.order(:position).first
      expect(result.poll.poll_contests.count).to eq(3)
      expect(first_poll_contest.title).to eq(first_source_contest.title)
      expect(first_poll_contest.school_election_contest).to eq(first_source_contest)
    end

    it "does not leave the default contest title" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result.poll.poll_contests.pluck(:title)).not_to include("기본")
    end

    it "stores school election contest source links on poll contests" do
      session = create_session_with_sources
      source_contests = session.school_election.school_election_contests.order(:position)

      result = described_class.new(session).call

      expect(result.poll.poll_contests.order(:position).map(&:school_election_contest)).to eq(source_contests.to_a)
    end

    it "creates poll options from school election candidates" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result.poll.poll_options.count).to eq(3)
      expect(result.poll.poll_options.order(:number).pluck(:name)).to include("김회장 (6학년 1반)")
    end

    it "stores school election candidate source links on poll options" do
      session = create_session_with_sources
      candidates = session.school_election.school_election_contests.flat_map do |contest|
        contest.school_election_candidates.order(:number).to_a
      end

      result = described_class.new(session).call

      expect(result.poll.poll_options.order(:id).map(&:school_election_candidate)).to match_array(candidates)
    end

    it "uses candidate number for poll option number" do
      session = create_session_with_sources

      result = described_class.new(session).call

      numbers = result.poll.poll_options.joins(:school_election_candidate).pluck(
        "poll_options.number",
        "school_election_candidates.number"
      )
      expect(numbers).to all(satisfy { |poll_number, candidate_number| poll_number == candidate_number })
    end

    it "stores candidate name with grade class label in poll option name" do
      session = create_session_with_sources

      result = described_class.new(session).call

      expect(result.poll.poll_options.pluck(:name)).to include(
        "김회장 (6학년 1반)",
        "이부회장 (6학년 2반)",
        "박부회장 (5학년 1반)"
      )
    end

    it "does not create poll option tallies" do
      session = create_session_with_sources

      expect do
        described_class.new(session).call
      end.not_to change(PollOptionTally, :count)
    end

    it "allows contests without candidates" do
      session = create(:school_election_classroom_session)
      session.school_election.ensure_default_contests!

      result = described_class.new(session).call

      expect(result).to be_success
      expect(result.poll.poll_contests.count).to eq(3)
      expect(result.poll.poll_options).to be_empty
    end

    it "fails when the school election has no contests" do
      session = create(:school_election_classroom_session)

      result = described_class.new(session).call

      expect(result).not_to be_success
      expect(result.error_message).to include("contest")
      expect(session.reload.poll).to be_nil
    end

    it "is idempotent when the session already has a poll" do
      session = create_session_with_sources
      existing_poll = create(:poll, user: session.teacher, participant_group: session.participant_group)
      session.update!(poll: existing_poll)

      expect do
        result = described_class.new(session).call

        expect(result).to be_success
        expect(result.poll).to eq(existing_poll)
      end.not_to change(Poll, :count)
    end

    it "does not leave a partial poll or session link if creation fails" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      session = create(:school_election_classroom_session, teacher: teacher, participant_group: participant_group)
      session.school_election.ensure_default_contests!

      result = described_class.new(session).call

      expect(result).not_to be_success
      expect(session.reload.poll).to be_nil
      expect(Poll.where(title: "#{session.school_election.title} - #{participant_group.name}")).to be_empty
    end
  end

  def create_session_with_sources
    session = create(:school_election_classroom_session)
    school_election = session.school_election
    president = create(:school_election_contest, school_election: school_election, position: 1, title: "회장")
    sixth_vice = create(:school_election_contest, school_election: school_election, position: 2, title: "6학년 부회장")
    fifth_vice = create(:school_election_contest, school_election: school_election, position: 3, title: "5학년 부회장")
    create(:school_election_candidate, school_election_contest: president, number: 1, name: "김회장", grade_class_label: "6학년 1반")
    create(:school_election_candidate, school_election_contest: sixth_vice, number: 1, name: "이부회장", grade_class_label: "6학년 2반")
    create(:school_election_candidate, school_election_contest: fifth_vice, number: 1, name: "박부회장", grade_class_label: "5학년 1반")
    session
  end
end
