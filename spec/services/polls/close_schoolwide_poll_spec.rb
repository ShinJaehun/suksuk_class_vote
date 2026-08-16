require "rails_helper"

RSpec.describe Polls::CloseSchoolwidePoll do
  include ActionCable::TestHelper

  def create_closable_poll(actor: create(:user, :admin))
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    poll = create(
      :poll,
      user: actor,
      school: school,
      school_managed: true
    )
    contest = create(:poll_contest, poll: poll, position: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    unless actor.admin?
      create(:school_membership, :manager, school: school, user: actor)
    end
    Polls::StartSchoolwidePoll.new(poll: poll, actor: actor).call
    Polls::StartSession.new(actor: teacher, poll_session: poll_session).call
    poll_session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = poll_session.poll_progress.current_poll_participant
    Polls::CloseSession.new(
      actor: teacher,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    [poll.reload, poll_session.reload]
  end

  it "closes the Poll and records a Poll-level event" do
    admin = create(:user, :admin)
    poll, poll_session = create_closable_poll(actor: admin)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_closed
    expect(poll.closed_at).to be_present
    expect(poll.stopped_at).to be_nil
    expect(poll.archived_at).to eq(poll.closed_at)
    expect(poll_session.reload.archived_at).to eq(poll.closed_at)
    expect(poll.poll_events.last).to have_attributes(
      actor: admin,
      poll_session: nil,
      event_type: "schoolwide_poll_closed"
    )
  end

  it "allows the same-School manager" do
    manager = create(:user)
    poll, = create_closable_poll(actor: manager)

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
  end

  it "archives stopped superseded history and its closed replacement without changing lifecycle" do
    poll, source = create_closable_poll
    original_started_at = source.started_at
    replacement = Polls::RevoteSchoolSession.new(poll_session: source, actor: poll.user).call.poll_session
    source.update!(status: :stopped, closed_at: nil, stopped_at: Time.current)
    original_stopped_at = source.stopped_at
    expect(Polls::StartSession.new(actor: replacement.operator, poll_session: replacement).call).to be_success
    replacement.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = replacement.poll_progress.current_poll_participant
    expect(
      Polls::CloseSession.new(
        actor: replacement.operator,
        poll_session: replacement,
        expected_current_poll_participant_id: current.id
      ).call
    ).to be_success

    expect(described_class.new(poll: poll.reload, actor: poll.user).call).to be_success
    expect(source.reload).to have_attributes(
      status: "stopped",
      started_at: original_started_at,
      closed_at: nil,
      stopped_at: original_stopped_at,
      archived_at: poll.reload.closed_at
    )
    expect(replacement.reload).to have_attributes(status: "closed", archived_at: poll.closed_at)
    expect(poll.poll_sessions).to contain_exactly(source, replacement)
  end

  it "rejects unfinished and stopped Sessions without changing the Poll" do
    %i[draft in_progress stopped].each do |status|
      poll, poll_session = create_closable_poll
      poll_session.update_column(:status, PollSession.statuses.fetch(status.to_s))

      expect do
        result = described_class.new(poll: poll, actor: poll.user).call
        expect(result).not_to be_success
      end.not_to change { [poll.reload.status, poll.closed_at, poll.archived_at, poll.poll_events.count] }
      expect(poll_session.reload.archived_at).to be_nil
    end
  end

  it "rolls back Poll and Session archives when event recording fails" do
    poll, poll_session = create_closable_poll
    events = poll.poll_events
    allow(poll).to receive(:poll_events).and_return(events)
    allow(events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(poll))

    expect(described_class.new(poll: poll, actor: poll.user).call).not_to be_success
    expect(poll.reload).to be_in_progress
    expect(poll.archived_at).to be_nil
    expect(poll_session.reload.archived_at).to be_nil
  end

  it "rejects duplicate close requests" do
    poll, = create_closable_poll
    actor = poll.user
    expect(described_class.new(poll: poll, actor: actor).call).to be_success

    expect(described_class.new(poll: poll.reload, actor: actor).call).not_to be_success
  end

  it "stops and archives unfinished child tests while preserving completed child data" do
    source, = create_closable_poll
    closed_at = 30.minutes.ago
    closed_test = create(:poll, school: source.school, school_managed: true,
                                test_source_poll: source,
                                status: :closed, started_at: 2.hours.ago,
                                closed_at: closed_at, archived_at: closed_at)
    closed_session = create(:poll_session, poll: closed_test,
                                           classroom: source.poll_sessions.first.classroom,
                                           operator: source.poll_sessions.first.operator,
                                           status: :closed, started_at: 2.hours.ago,
                                           closed_at: closed_at, archived_at: closed_at)
    closed_participant = create(:poll_participant, poll: closed_test,
                                                   poll_session: closed_session)
    closed_contest = create(:poll_contest, poll: closed_test)
    closed_option = create(:poll_option, poll: closed_test, poll_contest: closed_contest)
    closed_tally = create(:poll_option_tally, poll: closed_test,
                                              poll_session: closed_session,
                                              poll_option: closed_option,
                                              votes_count: 3)

    stopped_at = 20.minutes.ago
    stopped_test = create(:poll, school: source.school, school_managed: true,
                                 test_source_poll: source,
                                 status: :stopped, started_at: 2.hours.ago,
                                 stopped_at: stopped_at)
    stopped_session = create(:poll_session, poll: stopped_test,
                                            classroom: source.poll_sessions.first.classroom,
                                            operator: source.poll_sessions.first.operator,
                                            status: :stopped, started_at: 2.hours.ago,
                                            stopped_at: stopped_at)
    draft_test = create(:poll, school: source.school, school_managed: true,
                               test_source_poll: source)
    draft_session = create(:poll_session, poll: draft_test,
                                          classroom: source.poll_sessions.first.classroom,
                                          operator: source.poll_sessions.first.operator)
    running_test = create(:poll, school: source.school, school_managed: true,
                                 test_source_poll: source,
                                 status: :in_progress, started_at: 1.hour.ago)
    running_history = create(:poll_session, poll: running_test,
                                            classroom: source.poll_sessions.first.classroom,
                                            operator: source.poll_sessions.first.operator,
                                            status: :stopped, started_at: 90.minutes.ago,
                                            stopped_at: 70.minutes.ago)
    running_session = create(:poll_session, poll: running_test,
                                            classroom: running_history.classroom,
                                            operator: running_history.operator,
                                            replacement_of: running_history)
    running_session.update!(status: :in_progress, started_at: 1.hour.ago)
    running_progress = create(:poll_progress, poll: running_test, poll_session: running_session,
                                              ballot_status: :ballot_open)
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [running_session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [running_session, :ballot_screen])
    tally_count = PollOptionTally.count

    expect(described_class.new(poll: source, actor: source.user).call).to be_success

    closed_test.reload
    expect(closed_test).to have_attributes(status: "closed")
    expect(closed_test.closed_at).to be_within(0.000001).of(closed_at)
    expect(closed_test.archived_at).to be_within(0.000001).of(closed_at)

    closed_session.reload
    expect(closed_session).to have_attributes(status: "closed")
    expect(closed_session.closed_at).to be_within(0.000001).of(closed_at)
    expect(closed_session.archived_at).to be_within(0.000001).of(closed_at)

    expect(closed_participant.reload).to be_persisted
    expect(closed_tally.reload.votes_count).to eq(3)
    expect(PollOptionTally.count).to eq(tally_count)

    stopped_test.reload
    expect(stopped_test).to have_attributes(status: "stopped",
                                            archived_at: source.closed_at)
    expect(stopped_test.stopped_at).to be_within(0.000001).of(stopped_at)

    expect(stopped_session.reload).to have_attributes(status: "stopped",
                                                      archived_at: source.closed_at)
    expect(draft_test.reload).to have_attributes(status: "stopped", started_at: nil,
                                                 archived_at: source.closed_at)
    expect(draft_session.reload).to have_attributes(status: "stopped", started_at: nil,
                                                    archived_at: source.closed_at)
    expect(running_test.reload).to have_attributes(status: "stopped",
                                                   archived_at: source.closed_at)
    expect(running_session.reload).to have_attributes(status: "stopped",
                                                      archived_at: source.closed_at)
    expect(running_progress.reload).to be_ballot_locked
    expect(broadcasts(operation_stream).join).to include("원본 전교투표가 종료되어", "data-poll-session-terminal")
    expect(broadcasts(ballot_stream).join).to include("원본 전교투표가 종료되어", "data-poll-session-terminal")
    expect(running_history.reload).to have_attributes(status: "stopped",
                                                      archived_at: source.closed_at)
  end
end
