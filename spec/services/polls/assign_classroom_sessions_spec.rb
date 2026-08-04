require "rails_helper"

RSpec.describe Polls::AssignClassroomSessions do
  let(:school) { create(:school) }
  let(:manager) { create(:user) }
  let(:poll) do
    create(
      :poll,
      school: school,
      school_managed: true,
      participant_group: nil
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
    empty = create_classroom(active_student: false)

    [other_school, inactive, teacherless, empty].each do |invalid_classroom|
      expect do
        result = call_service(classrooms: [eligible, invalid_classroom])
        expect(result).not_to be_success
      end.not_to change(PollSession, :count)
    end
  end

  it "rejects every previously assigned Classroom regardless of Session status" do
    %i[draft in_progress closed stopped].each do |status|
      classroom = create_classroom
      create(:poll_session, poll: poll, classroom: classroom, status: status)
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
      school_managed: false,
      participant_group: nil
    )

    expect(call_service(classrooms: [classroom], target_poll: classroom_poll)).not_to be_success
    expect(call_service(classrooms: [])).not_to be_success
  end
end
