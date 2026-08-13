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

  it "allows a global admin to manage and operate a classroom PollSession" do
    poll_session, = create_poll_session
    admin = create(:user, :admin)

    expect(described_class.new(admin, poll_session)).to be_start
    expect(described_class.new(admin, poll_session)).to be_show
    expect(described_class.new(admin, poll_session)).to be_edit_definition
    expect(described_class.new(admin, poll_session)).to be_operate
  end

  it "rejects a same-school manager who is neither the operator nor classroom teacher" do
    poll_session, = create_poll_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    expect(described_class.new(manager, poll_session)).not_to be_start
    expect(described_class.new(manager, poll_session)).not_to be_show
    expect(described_class.new(manager, poll_session)).not_to be_edit_definition
  end

  it "allows the Classroom teacher to manage but not operate when another teacher is operator" do
    poll_session, teacher = create_poll_session
    operator = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: operator)
    poll_session.update!(operator: operator)

    expect(described_class.new(teacher, poll_session)).to be_start
    expect(described_class.new(teacher, poll_session)).to be_show
    expect(described_class.new(teacher, poll_session)).to be_edit_definition
    expect(described_class.new(teacher, poll_session)).not_to be_operate
  end

  it "allows the recorded operator to manage and operate without being the Classroom teacher" do
    poll_session, = create_poll_session
    operator = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: operator)
    poll_session.update!(operator: operator)

    expect(described_class.new(operator, poll_session)).to be_start
    expect(described_class.new(operator, poll_session)).to be_show
    expect(described_class.new(operator, poll_session)).to be_edit_definition
    expect(described_class.new(operator, poll_session)).to be_operate
  end

  it "allows only the recorded operator or a global admin to operate" do
    poll_session, classroom_teacher = create_poll_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    expect(described_class.new(classroom_teacher, poll_session)).to be_operate
    expect(described_class.new(manager, poll_session)).not_to be_operate
  end

  it "keeps an inactive School session readable but blocks runtime for teacher and admin" do
    poll_session, teacher = create_poll_session
    poll_session.classroom.school.update!(active: false)

    [teacher, create(:user, :admin)].each do |actor|
      policy = described_class.new(actor, poll_session)
      expect(policy).to be_show
      expect(policy).not_to be_start
      expect(policy).not_to be_operate
      expect(policy).not_to be_edit_definition
    end
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
    it "uses the lifecycle actor boundary for delete and archive" do
      session, teacher = create_poll_session
      operator = create(:user)
      create(:school_membership, school: session.classroom.school, user: operator)
      session.update!(operator: operator)
      manager = create(:user)
      create(:school_membership, :manager, school: session.classroom.school, user: manager)

      [operator, teacher, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, session)).to be_destroy_poll
      end
      expect(described_class.new(manager, session)).not_to be_destroy_poll

      session.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
      [operator, teacher, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, session)).to be_archive_poll
      end
      expect(described_class.new(manager, session)).not_to be_archive_poll
    end

    it "allows the operator, classroom teacher, and admin to stop" do
      poll_session, teacher = create_poll_session
      operator = create(:user)
      create(:school_membership, school: poll_session.classroom.school, user: operator)
      poll_session.update!(operator: operator)
      poll_session.update!(status: :in_progress, started_at: Time.current)
      manager = create(:user)
      create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

      [operator, teacher, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, poll_session)).to be_stop
      end
      expect(described_class.new(manager, poll_session)).not_to be_stop
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
      operator = create(:user)
      create(:school_membership, school: source.classroom.school, user: operator)
      source.update!(operator: operator)
      manager = create(:user)
      create(:school_membership, :manager, school: source.classroom.school, user: manager)
      source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                source_participant_slot: nil)
      expect(described_class.new(teacher, source)).to be_revote
      expect(described_class.new(operator, source)).to be_revote
      expect(described_class.new(create(:user, :admin), source)).to be_revote
      expect(described_class.new(manager, source)).not_to be_revote

      replacement = Polls::RevoteSession.new(actor: teacher, poll_session: source).call.poll_session
      replacement.update!(operator: operator)
      expect(described_class.new(teacher, source)).not_to be_revote
      expect(described_class.new(teacher, replacement)).to be_edit_replacement_roster
      expect(described_class.new(operator, replacement)).to be_edit_replacement_roster
      expect(described_class.new(create(:user, :admin), replacement)).to be_edit_replacement_roster
      replacement.update!(status: :in_progress, started_at: Time.current)
      expect(described_class.new(teacher, replacement)).not_to be_edit_replacement_roster
    end

    it "allows safe replacement definition editing for authorized classroom actors only" do
      source, teacher = create_poll_session
      source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                source_participant_slot: nil)
      replacement = Polls::RevoteSession.new(actor: teacher, poll_session: source).call.poll_session
      manager = create(:user)
      create(:school_membership, :manager, school: source.classroom.school, user: manager)
      unrelated = create(:user)
      create(:school_membership, school: source.classroom.school, user: unrelated)

      [teacher, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, replacement)).to be_edit_definition
      end
      replacement.update!(operator: unrelated)
      expect(described_class.new(unrelated, replacement)).to be_edit_definition
      expect(described_class.new(manager, replacement)).not_to be_edit_definition
      expect(described_class.new(manager, replacement)).not_to be_edit_replacement_roster
      expect(described_class.new(teacher, source)).not_to be_edit_definition

      replacement.update!(status: :in_progress, started_at: Time.current)
      expect(described_class.new(teacher, replacement)).not_to be_edit_definition
    end

    it "rejects revote for a closed source for every authorized actor" do
      source, teacher = create_poll_session
      source.update!(
        status: :closed,
        started_at: 1.hour.ago,
        closed_at: Time.current
      )
      manager = create(:user)
      create(:school_membership, :manager, school: source.classroom.school, user: manager)

      [teacher, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, source)).not_to be_revote
      end
      expect(described_class.new(manager, source)).not_to be_revote
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
      expect(described_class.new(manager, session)).to be_start
      expect(described_class.new(manager, session)).to be_show
      expect(described_class.new(teacher, session)).not_to be_school_revote
      expect(described_class.new(manager, session)).to be_school_revote
      expect(described_class.new(create(:user, :admin), session)).to be_school_revote
      expect(described_class.new(other_manager, session)).not_to be_school_revote

      draft_teacher = create(:user)
      create(:school_membership, school: school, user: draft_teacher)
      draft_classroom = create(:classroom, school: school, teacher: draft_teacher)
      draft_session = create(:poll_session, poll: poll, classroom: draft_classroom, operator: draft_teacher)
      expect(described_class.new(manager, draft_session)).not_to be_school_revote

      session.update!(status: :closed, closed_at: Time.current)
      expect(described_class.new(manager, session)).to be_school_revote

      session.update!(status: :stopped, closed_at: nil, stopped_at: Time.current)
      expect(described_class.new(manager, session)).not_to be_school_revote
      session.update!(status: :closed, closed_at: Time.current, stopped_at: nil)
      session.update_column(:archived_at, Time.current)
      expect(described_class.new(manager, session.reload)).not_to be_school_revote
      session.update_column(:archived_at, nil)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher, replacement_of: session)
      expect(described_class.new(manager, session.reload)).not_to be_school_revote

      poll.update!(status: :stopped, stopped_at: Time.current)
      expect(described_class.new(manager, session)).not_to be_school_revote
    end
  end
end
