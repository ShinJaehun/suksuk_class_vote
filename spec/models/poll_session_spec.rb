require "rails_helper"

RSpec.describe PollSession, type: :model do
  describe "factory" do
    subject(:poll_session) { build(:poll_session) }

    it "builds a valid draft session with its required associations and snapshot" do
      expect(poll_session).to be_valid
      expect(poll_session.poll).to be_present
      expect(poll_session.classroom).to be_present
      expect(poll_session.operator).to be_present
      expect(poll_session).to be_draft
      expect(poll_session.classroom_name_snapshot).to be_present
      expect(poll_session.operator_name_snapshot).to be_present
    end
  end

  describe "status" do
    it "uses the documented enum values" do
      expect(described_class.statuses).to eq(
        "draft" => 0,
        "in_progress" => 10,
        "closed" => 20,
        "stopped" => 30
      )
    end
  end

  describe "classroom_name_snapshot" do
    it "is required and limited to 100 characters" do
      expect(build(:poll_session, classroom_name_snapshot: nil)).to be_invalid
      expect(build(:poll_session, classroom_name_snapshot: "가" * 100)).to be_valid
      expect(build(:poll_session, classroom_name_snapshot: "가" * 101)).to be_invalid
    end

    it "stores a complete numeric classroom label" do
      classroom = create(:classroom, :with_teacher, class_label: "13")
      session = build(:poll_session, classroom: classroom, operator: classroom.teacher)

      expect(session.classroom_name_snapshot).to eq("2026학년도 4학년 13반")
    end

    it "stores a complete text classroom label without a suffix" do
      classroom = create(:classroom, :with_teacher, class_label: "생활교육실")
      session = build(:poll_session, classroom: classroom, operator: classroom.teacher)

      expect(session.classroom_name_snapshot).to eq("2026학년도 4학년 생활교육실")
    end
  end

  describe "school validation" do
    it "accepts a poll and classroom in the same school" do
      expect(build(:poll_session)).to be_valid
    end

    it "rejects a poll without a school" do
      classroom = create(:classroom, :with_teacher)
      poll = create(:poll, school: nil)

      expect(build(:poll_session, poll: poll, classroom: classroom, operator: classroom.teacher)).to be_invalid
    end

    it "rejects a classroom in another school" do
      poll = create(:poll, school: create(:school))
      classroom = create(:classroom, :with_teacher)

      expect(build(:poll_session, poll: poll, classroom: classroom, operator: classroom.teacher)).to be_invalid
    end
  end

  describe "operator" do
    it "accepts the classroom teacher as the operator" do
      expect(build(:poll_session)).to be_valid
    end

    it "accepts another teacher as the operator" do
      operator = create(:user)

      expect(build(:poll_session, operator: operator, operator_name_snapshot: operator.name)).to be_valid
    end

    it "accepts a global admin as the operator" do
      operator = create(:user, :admin)

      expect(build(:poll_session, operator: operator, operator_name_snapshot: operator.name)).to be_valid
    end

    it "requires an operator" do
      expect(build(:poll_session, operator: nil)).to be_invalid
    end
  end

  describe "operator_name_snapshot" do
    it "is required and limited to 100 characters" do
      expect(build(:poll_session, operator_name_snapshot: nil)).to be_invalid
      expect(build(:poll_session, operator_name_snapshot: "가" * 100)).to be_valid
      expect(build(:poll_session, operator_name_snapshot: "가" * 101)).to be_invalid
    end

    it "does not change when the operator or operator name changes" do
      session = create(:poll_session)
      original_snapshot = session.operator_name_snapshot

      session.operator.update!(name: "변경된 이름")
      session.update!(operator: create(:user))

      expect(session.reload.operator_name_snapshot).to eq(original_snapshot)
    end
  end

  describe "active session uniqueness" do
    let(:existing_session) { create(:poll_session) }

    it "rejects draft and in-progress combinations for the same poll and classroom" do
      existing_session

      expect(build(:poll_session, poll: existing_session.poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator, status: :draft)).to be_invalid
      expect(build(:poll_session, poll: existing_session.poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator, status: :in_progress)).to be_invalid

      existing_session.update!(status: :in_progress)

      expect(build(:poll_session, poll: existing_session.poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator, status: :draft)).to be_invalid
    end

    it "allows a draft after a closed or stopped session" do
      %i[closed stopped].each do |status|
        previous = create(:poll_session, status: status)

        expect(build(:poll_session, poll: previous.poll, classroom: previous.classroom,
                                    operator: previous.operator, status: :draft)).to be_valid
      end
    end

    it "allows multiple closed or stopped sessions" do
      %i[closed stopped].each do |status|
        previous = create(:poll_session, status: status)

        expect(build(:poll_session, poll: previous.poll, classroom: previous.classroom,
                                    operator: previous.operator, status: status)).to be_valid
      end
    end

    it "allows active sessions for a different poll or classroom" do
      existing_session
      other_poll = create(:poll, school: existing_session.classroom.school)
      other_classroom = create(:classroom, :with_teacher, school: existing_session.poll.school)

      expect(build(:poll_session, poll: other_poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator)).to be_valid
      expect(build(:poll_session, poll: existing_session.poll, classroom: other_classroom,
                                  operator: other_classroom.teacher)).to be_valid
    end
  end

  describe "terminal timestamps" do
    it "rejects simultaneous closed and stopped timestamps" do
      session = build(:poll_session, closed_at: Time.current, stopped_at: Time.current)

      expect(session).to be_invalid
      expect(session.errors[:base]).to be_present
    end
  end

  describe "deletion restrictions" do
    let!(:poll_session) { create(:poll_session) }

    it "prevents deletion of its poll" do
      expect(poll_session.poll.destroy).to be(false)
    end

    it "prevents deletion of its classroom" do
      expect(poll_session.classroom.destroy).to be(false)
    end

    it "prevents deletion of its operator" do
      expect(poll_session.operator.destroy).to be(false)
    end
  end
end
