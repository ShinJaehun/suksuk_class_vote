require "rails_helper"

RSpec.describe PollSessionPolicy do
  def create_poll_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    [create(:poll_session, poll: poll, classroom: classroom, operator: teacher), teacher]
  end

  it "allows a global admin" do
    poll_session, = create_poll_session

    expect(described_class.new(create(:user, :admin), poll_session)).to be_start
    expect(described_class.new(create(:user, :admin), poll_session)).to be_show
    expect(described_class.new(create(:user, :admin), poll_session)).to be_operate
  end

  it "allows a same-school manager" do
    poll_session, = create_poll_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    expect(described_class.new(manager, poll_session)).to be_start
    expect(described_class.new(manager, poll_session)).to be_show
  end

  it "allows the Classroom teacher" do
    poll_session, teacher = create_poll_session

    expect(described_class.new(teacher, poll_session)).to be_start
    expect(described_class.new(teacher, poll_session)).to be_show
    expect(described_class.new(teacher, poll_session)).to be_operate
  end

  it "allows only the recorded operator or a global admin to operate" do
    poll_session, classroom_teacher = create_poll_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    expect(described_class.new(classroom_teacher, poll_session)).to be_operate
    expect(described_class.new(manager, poll_session)).not_to be_operate
  end

  it "rejects another teacher, another-school manager, and membershipless teacher" do
    poll_session, = create_poll_session
    other_teacher = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: other_teacher)
    other_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_manager)

    expect(described_class.new(other_teacher, poll_session)).not_to be_start
    expect(described_class.new(other_manager, poll_session)).not_to be_start
    expect(described_class.new(create(:user), poll_session)).not_to be_start
    expect(described_class.new(other_teacher, poll_session)).not_to be_show
    expect(described_class.new(other_manager, poll_session)).not_to be_show
    expect(described_class.new(create(:user), poll_session)).not_to be_show
    expect(described_class.new(other_teacher, poll_session)).not_to be_operate
    expect(described_class.new(other_manager, poll_session)).not_to be_operate
    expect(described_class.new(create(:user), poll_session)).not_to be_operate
  end
end
