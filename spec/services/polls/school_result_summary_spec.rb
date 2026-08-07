require "rails_helper"

RSpec.describe Polls::SchoolResultSummary do
  def create_result_poll(school:, title:, source: nil)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         title: title, test_source_poll: source)
    contest = create(:poll_contest, poll: poll, title: "회장", position: 1)
    options = [1, 2].map do |number|
      create(:poll_option, poll: poll, poll_contest: contest, number: number)
    end
    [poll, options]
  end

  def create_result_classroom(school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    create(:classroom, school: school, teacher: teacher)
  end

  def add_closed_result(poll:, classroom:, options:, votes:)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: classroom.teacher,
                                    status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    options.zip(votes).each do |option, votes_count|
      create(:poll_option_tally, poll: poll, poll_session: session,
                                 poll_option: option, votes_count: votes_count)
    end
    session
  end

  def option_votes(poll)
    described_class.new(poll).contest_results.sole.option_results.map(&:votes_count)
  end

  it "excludes a closed source and includes only its closed replacement tally" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    contest = create(:poll_contest, poll: poll, title: "회장", position: 1)
    option = create(:poll_option, poll: poll, poll_contest: contest)
    source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                   status: :closed, started_at: 1.hour.ago, closed_at: 45.minutes.ago)
    replacement = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                        replacement_of: source)
    replacement.update!(status: :closed, started_at: 30.minutes.ago, closed_at: Time.current)
    create(:poll_option_tally, poll: poll, poll_session: source, poll_option: option, votes_count: 9)
    create(:poll_option_tally, poll: poll, poll_session: replacement, poll_option: option, votes_count: 3)

    summary = described_class.new(poll)

    expect(summary.closed_session_count).to eq(1)
    expect(summary.contest_results.sole.option_results.sole.votes_count).to eq(3)
    expect(summary.session_results.find { |result| result.poll_session == source }.included).to be(false)
    expect(summary.session_results.find { |result| result.poll_session == replacement }.included).to be(true)
  end

  it "keeps a source and multiple test Poll results completely isolated" do
    school = create(:school)
    classrooms = 3.times.map { create_result_classroom(school) }
    source, source_options = create_result_poll(school: school, title: "원본")
    test_one, test_one_options = create_result_poll(school: school, title: "테스트 1", source: source)
    test_two, test_two_options = create_result_poll(school: school, title: "테스트 2", source: source)

    add_closed_result(poll: source, classroom: classrooms[0], options: source_options, votes: [10, 5])
    add_closed_result(poll: test_one, classroom: classrooms[1], options: test_one_options, votes: [2, 3])
    add_closed_result(poll: test_two, classroom: classrooms[2], options: test_two_options, votes: [7, 1])

    expect(option_votes(source)).to eq([10, 5])
    expect(option_votes(test_one)).to eq([2, 3])
    expect(option_votes(test_two)).to eq([7, 1])
  end

  it "uses only a test Poll replacement result without affecting its source Poll" do
    school = create(:school)
    source_classroom = create_result_classroom(school)
    test_classroom = create_result_classroom(school)
    source, source_options = create_result_poll(school: school, title: "원본")
    test_poll, test_options = create_result_poll(school: school, title: "테스트", source: source)
    add_closed_result(poll: source, classroom: source_classroom, options: source_options, votes: [10, 5])

    test_poll.update!(
      status: :in_progress,
      started_at: 1.hour.ago
    )

    superseded = add_closed_result(
      poll: test_poll, classroom: test_classroom, options: test_options, votes: [8, 9]
    )
    replacement = create(:poll_session, poll: test_poll, classroom: test_classroom,
                                        operator: test_classroom.teacher,
                                        replacement_of: superseded)

    replacement.update!(
      status: :closed,
      started_at: 30.minutes.ago,
      closed_at: Time.current
    )

    test_options.zip([2, 3]).each do |option, votes_count|
      create(:poll_option_tally, poll: test_poll, poll_session: replacement,
                                 poll_option: option, votes_count: votes_count)
    end

    expect(option_votes(test_poll)).to eq([2, 3])
    expect(option_votes(source)).to eq([10, 5])
  end
end
