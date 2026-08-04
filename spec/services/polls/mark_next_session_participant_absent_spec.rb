require "rails_helper"

RSpec.describe Polls::MarkNextSessionParticipantAbsent do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    current = create(:poll_participant, poll: poll, poll_session: poll_session, number: 1, name: "조현")
    next_participant = create(:poll_participant, poll: poll, poll_session: poll_session, number: 2, name: "서코")
    following = create(:poll_participant, poll: poll, poll_session: poll_session, number: 3, name: "보기")
    create(:poll_participation, poll_participant: current, status: :completed)
    create(
      :poll_contest_completion,
      poll_participant: current,
      poll_contest: poll.default_poll_contest
    )
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: option, votes_count: 1)
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: poll.default_poll_contest
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_locked
    )

    [poll_session, progress, current, next_participant, following, operator]
  end

  it "marks the actual next pending participant absent without moving current" do
    poll_session, progress, current, next_participant, following, operator = create_execution

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(result).to be_success
    expect(next_participant.reload.poll_participation).to be_absent
    expect(next_participant.poll_participation.recorded_at).to be_present
    expect(following.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      current_poll_participant: current,
      ballot_status: "ballot_locked"
    )
    expect(poll_session.poll_events.last).to have_attributes(
      poll_participant: next_participant,
      event_type: "participant_marked_absent"
    )
  end

  it "rejects stale current input and an open ballot without partial changes" do
    poll_session, progress, current, next_participant, following, operator = create_execution

    stale_result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: next_participant.id
    ).call
    progress.update!(ballot_status: :ballot_open)
    open_result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(stale_result).not_to be_success
    expect(open_result).not_to be_success
    expect(next_participant.reload.poll_participation).to be_nil
    expect(following.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end
end
