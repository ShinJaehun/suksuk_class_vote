require "rails_helper"

RSpec.describe Polls::AssignClassroomSessions do
  let(:school) { create(:school) }
  let(:manager) { create(:user) }
  let(:poll) do
    create(
      :poll,
      school: school,
      school_managed: true
    )
  end

  before do
    create(:school_membership, :manager, school: school, user: manager)
  end

  def create_classroom(school: self.school, active: true, teacher: nil, active_student: true)
    teacher ||= create(:user)
    create(:school_membership, school: school, user: teacher) unless teacher.school_membership
    classroom = create(:classroom, school: school, teacher: teacher, active: active)
    create(:student, classroom: classroom, active: true) if active_student
    classroom
  end

  def call_service(classrooms:, actor: manager, target_poll: poll)
    described_class.new(
      poll: target_poll,
      classroom_ids: classrooms.map(&:id),
      actor: actor
    ).call
  end

  it "atomically creates one draft Session per Classroom with teacher snapshots" do
    first = create_classroom(teacher: create(:user, name: "첫 담임"))
    second = create_classroom(teacher: create(:user, name: "둘째 담임"))
    result = nil

    expect do
      result = call_service(classrooms: [first, second])
    end.to change(PollSession, :count).by(2)
      .and change(PollParticipant, :count).by(0)
      .and change(PollParticipation, :count).by(0)
      .and change(PollProgress, :count).by(0)
      .and change(PollOptionTally, :count).by(0)
      .and change(PollContestTally, :count).by(0)
      .and change(PollEvent, :count).by(0)

    expect(result).to be_success
    expect(result.poll_sessions).to contain_exactly(
      an_object_having_attributes(
        classroom: first,
        operator: first.teacher,
        classroom_name_snapshot: "2026학년도 4학년 #{first.formatted_class_label}",
        operator_name_snapshot: "첫 담임",
        status: "draft"
      ),
      an_object_having_attributes(
        classroom: second,
        operator: second.teacher,
        classroom_name_snapshot: "2026학년도 4학년 #{second.formatted_class_label}",
        operator_name_snapshot: "둘째 담임",
        status: "draft"
      )
    )
    expect(poll.reload).to be_draft
  end

  it "creates Sessions from Classroom state reloaded after locking the Poll" do
    original_teacher = create(:user, name: "기존 담임")
    current_teacher = create(:user, name: "현재 담임")
    classroom = create_classroom(teacher: original_teacher)
    create(:school_membership, school: school, user: current_teacher)

    allow(poll).to receive(:lock!).and_wrap_original do |original|
      original.call
      classroom.update!(teacher: current_teacher)
    end

    result = call_service(classrooms: [classroom])

    expect(result).to be_success
    expect(result.poll_sessions.sole).to have_attributes(
      classroom: classroom,
      operator: current_teacher,
      operator_name_snapshot: "현재 담임"
    )
  end

  it "creates Sessions in School order after locking Classrooms by id" do
    upper_grade = create_classroom
    lower_grade = create_classroom
    upper_grade.update!(grade: 6)
    lower_grade.update!(grade: 1)

    result = call_service(classrooms: [upper_grade, lower_grade])

    expect(result.poll_sessions.map(&:classroom)).to eq([lower_grade, upper_grade])
  end

  it "suppresses create callbacks and performs one final batch runtime broadcast" do
    first = create_classroom
    second = create_classroom
    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:new)
      .with(poll: poll, classroom: first)
    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:new)
      .with(poll: poll, classroom: second)
    expect(Polls::BroadcastSchoolwideSessionState).to receive(:for_batch)
      .once.with(poll: poll, actor: manager).and_call_original

    expect(call_service(classrooms: [first, second])).to be_success
  end

  it "allows global admin and the same-School manager only" do
    classroom = create_classroom
    admin = create(:user, :admin)
    other_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_manager)

    expect(call_service(classrooms: [classroom], actor: admin)).to be_success

    another_classroom = create_classroom
    expect(call_service(classrooms: [another_classroom])).to be_success

    blocked_classroom = create_classroom
    expect(call_service(classrooms: [blocked_classroom], actor: other_manager)).not_to be_success
    expect(call_service(classrooms: [blocked_classroom], actor: create(:user))).not_to be_success
  end

  it "rolls back all Sessions when any Classroom is ineligible" do
    eligible = create_classroom
    other_school = create_classroom(school: create(:school))
    inactive = create_classroom(active: false)
    teacherless = create(:classroom, school: school, teacher: nil)
    create(:student, classroom: teacherless, active: true)

    [other_school, inactive, teacherless].each do |invalid_classroom|
      expect do
        result = call_service(classrooms: [eligible, invalid_classroom])
        expect(result).not_to be_success
      end.not_to change(PollSession, :count)
    end
  end

  it "does not perform a final batch broadcast when assignment fails" do
    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:for_batch)

    expect(call_service(classrooms: [])).not_to be_success
  end

  it "assigns an active teacher-led Classroom before any Students are registered" do
    classroom = create_classroom(active_student: false)

    expect do
      result = call_service(classrooms: [classroom])
      expect(result).to be_success
    end.to change(PollSession, :count).by(1)

    expect(poll.poll_sessions.sole).to have_attributes(classroom: classroom, status: "draft")
  end

  it "rejects every previously assigned Classroom regardless of Session status" do
    %i[draft in_progress closed stopped].each do |status|
      classroom = create_classroom
      create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        status: status,
        started_at: (1.hour.ago unless status == :draft),
        closed_at: (Time.current if status == :closed),
        stopped_at: (Time.current if status == :stopped)
      )
      fresh_classroom = create_classroom

      expect do
        result = call_service(classrooms: [fresh_classroom, classroom])
        expect(result).not_to be_success
      end.not_to change(PollSession, :count)
    end
  end

  it "rejects a non-School-managed Poll and an empty selection" do
    classroom = create_classroom
    classroom_poll = create(
      :poll,
      school: school,
      school_managed: false
    )

    expect(call_service(classrooms: [classroom], target_poll: classroom_poll)).not_to be_success
    expect(call_service(classrooms: [])).not_to be_success
  end

  it "allows a draft test Poll to use any eligible Classroom in its School" do
    source_classroom = create_classroom
    additional = create_classroom
    source = create(:poll, school: school, school_managed: true)
    create(:poll_session, poll: source, classroom: source_classroom, operator: source_classroom.teacher)
    test_poll = create(:poll, school: school, school_managed: true, test_source_poll: source)

    expect(call_service(classrooms: [additional], target_poll: test_poll)).to be_success
    expect(test_poll.poll_sessions.sole.classroom).to eq(additional)
    expect(source.poll_sessions.map(&:classroom)).to contain_exactly(source_classroom)

    another_eligible = create_classroom
    test_poll.update!(status: :in_progress, started_at: Time.current)
    expect(call_service(classrooms: [another_eligible], target_poll: test_poll)).not_to be_success
  end
end
