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

  describe "classroom lifecycle permissions" do
    it "allows the operator, classroom teacher, same-school manager, and admin" do
      poll_session, teacher = create_poll_session
      poll_session.update!(status: :in_progress, started_at: Time.current)
      manager = create(:user)
      create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

      [teacher, manager, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, poll_session)).to be_stop
      end
    end

    it "rejects unrelated teachers and every school-managed session" do
      poll_session, = create_poll_session
      poll_session.update!(status: :in_progress, started_at: Time.current)
      unrelated = create(:user)
      create(:school_membership, school: poll_session.classroom.school, user: unrelated)
      expect(described_class.new(unrelated, poll_session)).not_to be_stop

      poll_session.poll.update!(school_managed: true)
      expect(described_class.new(create(:user, :admin), poll_session)).not_to be_stop
      poll_session.update!(status: :stopped, stopped_at: Time.current)
      expect(described_class.new(create(:user, :admin), poll_session)).not_to be_revote
    end

    it "allows revote and replacement roster editing only in their matching states" do
      source, teacher = create_poll_session
      source.update!(status: :stopped, stopped_at: Time.current)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                source_participant_slot: nil)
      expect(described_class.new(teacher, source)).to be_revote

      replacement = Polls::RevoteSession.new(actor: teacher, poll_session: source).call.poll_session
      expect(described_class.new(teacher, source)).not_to be_revote
      expect(described_class.new(teacher, replacement)).to be_edit_replacement_roster
      replacement.update!(status: :in_progress, started_at: Time.current)
      expect(described_class.new(teacher, replacement)).not_to be_edit_replacement_roster
    end

    it "allows safe replacement definition editing for authorized classroom actors only" do
      source, teacher = create_poll_session
      source.update!(status: :stopped, stopped_at: Time.current)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                source_participant_slot: nil)
      replacement = Polls::RevoteSession.new(actor: teacher, poll_session: source).call.poll_session
      manager = create(:user)
      create(:school_membership, :manager, school: source.classroom.school, user: manager)
      unrelated = create(:user)
      create(:school_membership, school: source.classroom.school, user: unrelated)

      [teacher, manager, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, replacement)).to be_edit_definition
      end
      expect(described_class.new(unrelated, replacement)).not_to be_edit_definition
      expect(described_class.new(teacher, source)).not_to be_edit_definition

      replacement.update!(status: :in_progress, started_at: Time.current)
      expect(described_class.new(teacher, replacement)).not_to be_edit_definition
    end

    it "rejects revote for a closed source for every authorized actor" do
      source, teacher = create_poll_session
      source.update!(status: :closed, closed_at: Time.current)
      manager = create(:user)
      create(:school_membership, :manager, school: source.classroom.school, user: manager)

      [teacher, manager, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, source)).not_to be_revote
      end
    end
  end


  describe "schoolwide revote permissions" do
    it "allows only the School manager and admin for active in-progress or closed Sessions" do
      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                           status: :in_progress, started_at: Time.current)
      session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                      status: :in_progress, started_at: Time.current)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)

      expect(described_class.new(teacher, session)).not_to be_stop
      expect(described_class.new(teacher, session)).not_to be_school_revote
      expect(described_class.new(manager, session)).to be_school_revote
      expect(described_class.new(create(:user, :admin), session)).to be_school_revote
      expect(described_class.new(other_manager, session)).not_to be_school_revote

      session.update!(status: :closed, closed_at: Time.current)
      expect(described_class.new(manager, session)).to be_school_revote
      poll.update!(status: :stopped, stopped_at: Time.current)
      expect(described_class.new(manager, session)).not_to be_school_revote
    end
  end
end
