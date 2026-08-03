require "rails_helper"

RSpec.describe "PollSession supervised participant flow", type: :request do
  include Devise::Test::IntegrationHelpers

  it "keeps a final current participant until the operator approves the next student" do
    poll, poll_session, progress, first, second, operator = create_execution
    sign_in operator

    patch mark_current_participant_absent_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(first.reload.poll_participation).to be_absent
    expect(progress.reload).to have_attributes(
      current_poll_participant: first,
      ballot_status: "ballot_locked"
    )

    patch advance_participant_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: first.id
    }

    expect(progress.reload).to have_attributes(
      current_poll_participant: second,
      ballot_status: "ballot_open"
    )
  end

  it "rejects a mismatched parent and a stale current participant" do
    poll, poll_session, progress, first, second, operator = create_execution
    create(:poll_participation, poll_participant: first, status: :completed)
    sign_in operator
    other_poll = create(:poll, user: operator)

    patch advance_participant_poll_poll_session_path(other_poll, poll_session), params: {
      expected_current_poll_participant_id: first.id
    }

    expect(response).to have_http_status(:not_found)

    patch advance_participant_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: second.id
    }

    expect(progress.reload.current_poll_participant).to eq(first)
  end

  private

  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    first = create(:poll_participant, poll: poll, poll_session: poll_session, number: 1)
    second = create(:poll_participant, poll: poll, poll_session: poll_session, number: 2)
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: first,
      ballot_status: :ballot_locked
    )

    [poll, poll_session, progress, first, second, operator]
  end
end
