require "rails_helper"

RSpec.describe Polls::ArchiveClassroomPoll do
  def create_target(status: :closed)
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: status, started_at: 1.hour.ago,
                                    closed_at: (Time.current if status == :closed))
    [poll, session, teacher]
  end

  it "archives a closed Poll and every Session at the same time" do
    poll, session, teacher = create_target

    result = described_class.new(poll: poll, actor: teacher).call

    expect(result).to be_success
    expect(poll.reload.archived_at).to be_present
    expect(session.reload.archived_at).to eq(poll.archived_at)
    expect(PollPolicy.new(teacher, poll)).not_to be_destroy
  end

  it "rejects in-progress Polls and unauthorized actors" do
    poll, session, teacher = create_target(status: :in_progress)
    manager = create(:user)
    create(:school_membership, :manager, school: poll.school, user: manager)

    expect(described_class.new(poll: poll, actor: teacher).call).not_to be_success
    expect(described_class.new(poll: poll, actor: manager).call).not_to be_success
    expect(poll.reload.archived_at).to be_nil
    expect(session.reload.archived_at).to be_nil
  end
end
