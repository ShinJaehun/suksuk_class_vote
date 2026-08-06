require "rails_helper"

RSpec.describe Polls::SchoolResultSummary do
  it "excludes a stopped source and includes only its closed replacement tally" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    contest = create(:poll_contest, poll: poll, title: "회장", position: 1)
    option = create(:poll_option, poll: poll, poll_contest: contest)
    source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                   status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
    replacement = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                        replacement_of: source)
    replacement.update!(status: :closed, started_at: 30.minutes.ago, closed_at: Time.current)
    create(:poll_option_tally, poll: poll, poll_session: source, poll_option: option, votes_count: 9)
    create(:poll_option_tally, poll: poll, poll_session: replacement, poll_option: option, votes_count: 3)

    summary = described_class.new(poll)

    expect(summary.closed_session_count).to eq(1)
    expect(summary.contest_results.sole.option_results.sole.votes_count).to eq(3)
  end
end
