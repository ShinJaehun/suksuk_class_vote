require "rails_helper"

RSpec.describe Polls::CreateDefinitionWithSession do
  let(:school) { create(:school) }
  let(:actor) { create(:user) }
  let(:classroom) { create_classroom(school: school, teacher: actor) }

  let(:poll_attributes) do
    {
      title: "우리 반 의견 투표",
      kind: "discussion",
      poll_contests_attributes: {
        "0" => {
          title: "의견 선택",
          poll_options_attributes: {
            "0" => { number: 2, name: "두 번째 의견" },
            "1" => { number: 1, name: "첫 번째 의견" }
          }
        }
      }
    }
  end

  def create_classroom(school:, teacher:, active: true, active_student_count: 1)
    unless teacher.school_membership
      create(:school_membership, school: school, user: teacher)
      teacher.reload
    end
    classroom = create(:classroom, school: school, teacher: teacher, active: active)
    active_student_count.times { create(:student, classroom: classroom, active: true) }
    classroom
  end

  def call_service(
    actor: self.actor,
    classroom: self.classroom,
    poll_attributes: self.poll_attributes,
    school_managed: false
  )
    described_class.new(
      actor: actor,
      classroom: classroom,
      poll_attributes: poll_attributes,
      school_managed: school_managed
    ).call
  end

  describe "successful creation" do
    it "atomically creates a school Poll definition and its first draft PollSession" do
      result = nil

      expect do
        result = call_service
      end.to change(Poll, :count).by(1).and change(PollSession, :count).by(1)

      expect(result).to be_success
      expect(result.errors).to be_empty
      expect(result.poll).to have_attributes(
        user: actor,
        school: school,
        participant_group: nil,
        status: "draft",
        archived_at: nil
      )
      expect(result.poll_session).to have_attributes(
        poll: result.poll,
        classroom: classroom,
        operator: actor,
        status: "draft"
      )
    end

    it "preserves the Poll content and option number order" do
      result = call_service

      expect(result.poll).to have_attributes(title: "우리 반 의견 투표", kind: "discussion")
      expect(result.poll.poll_contests.pluck(:title)).to eq(["의견 선택"])
      expect(result.poll.default_poll_options.order(:number).pluck(:number, :name)).to eq(
        [[1, "첫 번째 의견"], [2, "두 번째 의견"]]
      )
    end

    it "stores numeric classroom and operator snapshots without callbacks" do
      classroom.update!(class_label: "1")
      result = call_service

      expect(result.poll_session.classroom_name_snapshot).to eq("2026학년도 4학년 1반")
      expect(result.poll_session.operator_name_snapshot).to eq(actor.name)

      actor.update!(name: "변경된 이름")
      expect(result.poll_session.reload.operator_name_snapshot).not_to eq(actor.name)
    end

    it "stores a text classroom label without adding a suffix" do
      text_classroom = create_classroom(school: school, teacher: actor)
      text_classroom.update!(grade: 6, class_label: "생활교육실")

      result = call_service(classroom: text_classroom)

      expect(result.poll_session.classroom_name_snapshot).to eq("2026학년도 6학년 생활교육실")
    end
  end

  describe "operator authorization" do
    it "allows the classroom teacher" do
      expect(call_service).to be_success
    end

    it "allows a same-school manager to operate another teacher's classroom" do
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      classroom_teacher = create(:user)
      managed_classroom = create_classroom(school: school, teacher: classroom_teacher)

      result = call_service(actor: manager, classroom: managed_classroom)

      expect(result).to be_success
      expect(result.poll_session.operator).to eq(manager)
      expect(managed_classroom.reload.teacher).to eq(classroom_teacher)
    end

    it "allows a global admin without a SchoolMembership" do
      admin = create(:user, :admin)

      result = call_service(actor: admin)

      expect(result).to be_success
      expect(result.poll_session.operator).to eq(admin)
    end

    it "uses the Classroom teacher for a School-managed PollSession" do
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      classroom_teacher = create(:user, name: "담임교사")
      managed_classroom = create_classroom(school: school, teacher: classroom_teacher)

      result = call_service(
        actor: manager,
        classroom: managed_classroom,
        school_managed: true
      )

      expect(result).to be_success
      expect(result.poll_session).to have_attributes(
        operator: classroom_teacher,
        operator_name_snapshot: "담임교사"
      )
    end

    it "rejects a regular teacher for another teacher's classroom" do
      other_teacher = create(:user)
      create(:school_membership, school: school, user: other_teacher)

      expect do
        expect(call_service(actor: other_teacher)).not_to be_success
      end.not_to change(Poll, :count)
    end

    it "rejects a teacher whose membership belongs to another school" do
      other_teacher = create(:user)
      create(:school_membership, school: create(:school), user: other_teacher)

      expect(call_service(actor: other_teacher)).not_to be_success
    end

    it "rejects a manager from another school" do
      manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: manager)

      expect(call_service(actor: manager)).not_to be_success
    end

    it "rejects a missing actor without creating records" do
      expect do
        expect(call_service(actor: nil)).not_to be_success
      end.not_to change(Poll, :count)
    end
  end

  describe "Classroom eligibility" do
    it "rejects an inactive Classroom" do
      inactive_classroom = create_classroom(school: school, teacher: actor, active: false)

      expect(call_service(classroom: inactive_classroom)).not_to be_success
    end

    it "rejects a Classroom without active Students" do
      empty_classroom = create_classroom(
        school: school,
        teacher: actor,
        active_student_count: 0
      )

      expect(call_service(classroom: empty_classroom)).not_to be_success
    end

    it "rejects a Classroom containing only inactive Students" do
      inactive_students_classroom = create_classroom(
        school: school,
        teacher: actor,
        active_student_count: 0
      )
      create(:student, classroom: inactive_students_classroom, active: false)

      expect(call_service(classroom: inactive_students_classroom)).not_to be_success
    end

    it "accepts a Classroom with at least one active Student" do
      create(:student, classroom: classroom, active: false)

      expect(call_service).to be_success
    end
  end

  describe "protected Poll attributes" do
    it "overrides external ownership, source, and lifecycle attributes" do
      other_user = create(:user)
      other_school = create(:school)
      participant_group = create(:participant_group, :with_participant_slot)
      attributes = poll_attributes.merge(
        user_id: other_user.id,
        school_id: other_school.id,
        participant_group_id: participant_group.id,
        status: "in_progress",
        archived_at: Time.current
      )

      result = call_service(poll_attributes: attributes)

      expect(result).to be_success
      expect(result.poll).to have_attributes(
        user: actor,
        school: school,
        participant_group: nil,
        status: "draft",
        archived_at: nil
      )
    end
  end

  describe "transaction rollback" do
    it "rolls back Poll, content, and PollSession when an option is invalid" do
      invalid_attributes = poll_attributes.deep_dup
      invalid_attributes[:poll_contests_attributes]["0"][:poll_options_attributes]["1"][:name] = ""
      original_counts = {
        polls: Poll.count,
        contests: PollContest.count,
        options: PollOption.count,
        sessions: PollSession.count
      }

      result = call_service(poll_attributes: invalid_attributes)

      expect(result).not_to be_success
      expect(Poll.count).to eq(original_counts[:polls])
      expect(PollContest.count).to eq(original_counts[:contests])
      expect(PollOption.count).to eq(original_counts[:options])
      expect(PollSession.count).to eq(original_counts[:sessions])
    end
  end

  describe "legacy isolation" do
    it "does not change existing legacy Poll roster records" do
      legacy_poll = create(:poll)
      group_count = ParticipantGroup.count
      slot_count = ParticipantSlot.count

      result = call_service

      expect(result).to be_success
      expect(legacy_poll.reload.participant_group).to be_present
      expect(ParticipantGroup.count).to eq(group_count)
      expect(ParticipantSlot.count).to eq(slot_count)
    end
  end
end
