require "rails_helper"

RSpec.describe Polls::UnassignClassroomSessions do
  let(:school) { create(:school) }
  let(:manager) { create(:user) }
  let(:poll) { create(:poll, school: school, school_managed: true, participant_group: nil) }

  before do
    create(:school_membership, :manager, school: school, user: manager)
  end

  def classroom(grade: 4)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher, grade: grade)
    create(:student, classroom: classroom)
    classroom
  end

  def session_for(target_poll: poll, grade: 4)
    room = classroom(grade: grade)
    create(:poll_session, poll: target_poll, classroom: room, operator: room.teacher)
  end

  def call(sessions, target_poll: poll)
    described_class.new(poll: target_poll, poll_sessions: sessions, actor: manager).call
  end

  it "removes draft Sessions individually and for one grade while preserving other grades" do
    first = session_for
    second = session_for
    third = session_for
    fifth = session_for(grade: 5)

    expect { call([first]) }.to change(poll.poll_sessions, :count).by(-1)
    expect(call([second, third])).to be_success
    expect(poll.poll_sessions.reload).to contain_exactly(fifth)
  end

  it "also removes a safe draft Session from a test Poll" do
    source = poll
    test_poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                              test_source_poll: source)
    session = session_for(target_poll: test_poll)

    expect do
      result = call([session], target_poll: test_poll)
      expect(result).to be_success
    end.to change(test_poll.poll_sessions, :count).by(-1)
  end

  it "rejects non-draft Polls, another Poll's Session, and Sessions with runtime" do
    session = session_for
    other_poll = create(:poll, school: school, school_managed: true, participant_group: nil)
    other_session = session_for(target_poll: other_poll)

    expect(call([other_session])).not_to be_success
    create(:poll_participant, poll: poll, poll_session: session,
                              source_participant_slot: nil, number: 1, name: "학생")
    safe = session_for
    expect(call([safe, session])).not_to be_success
    expect(PollSession.where(id: [safe.id, session.id]).count).to eq(2)

    poll.update!(status: :in_progress, started_at: Time.current)
    fresh = session_for
    expect(call([fresh])).not_to be_success
    expect(PollSession.where(id: [session.id, other_session.id, fresh.id]).count).to eq(3)
  end

  it "rejects replacement and superseded history Sessions" do
    original = session_for
    poll.update!(status: :in_progress, started_at: 1.hour.ago)
    original.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: 30.minutes.ago)
    replacement = create(:poll_session, poll: poll, classroom: original.classroom,
                                         operator: original.operator, replacement_of: original)
    poll.update_columns(status: Poll.statuses.fetch("draft"), started_at: nil)

    expect(call([original])).not_to be_success
    expect(call([replacement])).not_to be_success
    expect(PollSession.where(id: [original.id, replacement.id]).count).to eq(2)
  end
end
