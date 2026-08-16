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

  describe "schoolwide runtime callback" do
    it "keeps create and status update broadcasts for an isolated School-managed Session" do
      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true)
      broadcaster = instance_double(Polls::BroadcastSchoolwideSessionState, call: nil)
      expect(Polls::BroadcastSchoolwideSessionState).to receive(:new)
        .with(poll: poll, classroom: classroom).twice.and_return(broadcaster)

      poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
      poll_session.update!(status: :in_progress, started_at: Time.current)
    end

    it "restores callback broadcasting after a suppressed block raises" do
      expect do
        described_class.with_schoolwide_runtime_broadcast_suppressed { raise "failure" }
      end.to raise_error("failure")

      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true)
      broadcaster = instance_double(Polls::BroadcastSchoolwideSessionState, call: nil)
      expect(Polls::BroadcastSchoolwideSessionState).to receive(:new)
        .with(poll: poll, classroom: classroom).and_return(broadcaster)

      create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
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
      poll = build(:poll, school: nil)

      poll_session = build(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: classroom.teacher
      )

      expect(poll_session).to be_invalid
      expect(poll_session.errors[:poll]).to include("must have a school")
    end

    it "rejects a classroom in another school" do
      poll = create(
        :poll,
        school: create(:school)
      )
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
                                   operator: existing_session.operator, status: :in_progress,
                                   started_at: Time.current)).to be_invalid

      existing_session.update!(status: :in_progress, started_at: Time.current)

      expect(build(:poll_session, poll: existing_session.poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator, status: :draft)).to be_invalid
    end

    it "allows a draft after a closed or stopped session" do
      %i[closed stopped].each do |status|
        timestamps = {
          started_at: 1.hour.ago,
          closed_at: (Time.current if status == :closed),
          stopped_at: (Time.current if status == :stopped)
        }
        previous = create(
          :poll_session,
          status: status,
          **timestamps
        )
        expect(build(:poll_session, poll: previous.poll, classroom: previous.classroom,
                                    operator: previous.operator, status: :draft)).to be_valid
      end
    end

    it "allows multiple closed or stopped sessions" do
      %i[closed stopped].each do |status|
        timestamps = {
          started_at: 1.hour.ago,
          closed_at: (Time.current if status == :closed),
          stopped_at: (Time.current if status == :stopped)
        }
        previous = create(
          :poll_session,
          status: status,
          **timestamps
        )
        expect(build(:poll_session, poll: previous.poll, classroom: previous.classroom,
                                    operator: previous.operator, status: status,
                                    **timestamps)).to be_valid
      end
    end

    it "allows active sessions for a different poll or classroom" do
      existing_session
      other_poll = create(
        :poll,
        school: existing_session.classroom.school
      )
      other_classroom = create(:classroom, :with_teacher, school: existing_session.poll.school)

      expect(build(:poll_session, poll: other_poll, classroom: existing_session.classroom,
                                  operator: existing_session.operator)).to be_valid
      expect(build(:poll_session, poll: existing_session.poll, classroom: other_classroom,
                                  operator: other_classroom.teacher)).to be_valid
    end
  end

  describe "lifecycle timestamps" do
    it "rejects lifecycle timestamps on a draft" do
      expect(build(:poll_session, started_at: Time.current)).to be_invalid
      expect(build(:poll_session, closed_at: Time.current)).to be_invalid
      expect(build(:poll_session, stopped_at: Time.current)).to be_invalid
    end

    it "requires only started_at while in progress" do
      expect(build(:poll_session, status: :in_progress)).to be_invalid
      expect(build(:poll_session, status: :in_progress, started_at: Time.current)).to be_valid
      expect(build(:poll_session, status: :in_progress, started_at: 1.hour.ago,
                                  closed_at: Time.current)).to be_invalid
      expect(build(:poll_session, status: :in_progress, started_at: 1.hour.ago,
                                  stopped_at: Time.current)).to be_invalid
    end

    it "requires ordered started_at and closed_at when closed" do
      expect(build(:poll_session, status: :closed)).to be_invalid
      expect(build(:poll_session, status: :closed, started_at: 1.hour.ago,
                                  closed_at: Time.current)).to be_valid
      expect(build(:poll_session, status: :closed, started_at: Time.current,
                                  closed_at: 1.hour.ago)).to be_invalid
      expect(build(:poll_session, status: :closed, started_at: 1.hour.ago,
                                  closed_at: Time.current, stopped_at: Time.current)).to be_invalid
    end

    it "requires ordered started_at and stopped_at for a regular Poll" do
      expect(build(:poll_session, status: :stopped, stopped_at: Time.current)).to be_invalid
      expect(build(:poll_session, status: :stopped, started_at: 1.hour.ago,
                                  stopped_at: Time.current)).to be_valid
      expect(build(:poll_session, status: :stopped, started_at: Time.current,
                                  stopped_at: 1.hour.ago)).to be_invalid
    end

    it "allows an unstarted stopped Session only when its School Poll is stopped" do
      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)

      expect(build(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                  status: :stopped, stopped_at: poll.stopped_at)).to be_valid
      poll.update_columns(status: Poll.statuses.fetch("in_progress"), stopped_at: nil)
      expect(build(:poll_session, poll: poll.reload, classroom: classroom, operator: teacher,
                                  status: :stopped, stopped_at: Time.current)).to be_invalid
    end
  end

  describe "replacement relationship" do
    def stopped_session(status: :stopped)
      create(:poll_session, status: status, started_at: 1.hour.ago,
                            stopped_at: (Time.current if status == :stopped),
                            closed_at: (Time.current if status == :closed))
    end

    it "links a replacement using a separate draft poll in the same classroom" do
      source = stopped_session
      replacement_poll = create(:poll, user: source.poll.user, school: source.poll.school)
      replacement = create(
        :poll_session,
        poll: replacement_poll,
        classroom: source.classroom,
        operator: source.operator,
        replacement_of: source
      )

      expect(replacement).to be_replacement
      expect(source.reload).to be_superseded
      expect(source.replacement_session).to eq(replacement)
      expect(replacement.poll).not_to eq(source.poll)
    end

    it "rejects a closed or non-stopped source, a different classroom, and self-reference" do
      source = create(:poll_session)
      expect(build(:poll_session, poll: source.poll, classroom: source.classroom,
                                  operator: source.operator, replacement_of: source)).to be_invalid

      closed_source = stopped_session(status: :closed)
      closed_poll = create(:poll, user: closed_source.poll.user, school: closed_source.poll.school)
      expect(build(:poll_session, poll: closed_poll, classroom: closed_source.classroom,
                                  operator: closed_source.operator, replacement_of: closed_source)).to be_invalid

      source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      different_classroom = create(:classroom, :with_teacher, school: source.poll.school)
      expect(build(:poll_session, poll: source.poll, classroom: different_classroom,
                                  operator: different_classroom.teacher, replacement_of: source)).to be_invalid

      replacement = build(:poll_session, poll: source.poll, classroom: source.classroom, operator: source.operator)
      replacement.replacement_of = replacement
      expect(replacement).to be_invalid
    end


    it "rejects a school-managed source or replacement poll and a non-draft replacement poll" do
      source = stopped_session
      replacement_poll = create(:poll, user: source.poll.user, school: source.poll.school)

      source.poll.update!(school_managed: true)
      expect(build(:poll_session, poll: replacement_poll, classroom: source.classroom,
                                  operator: source.operator, replacement_of: source)).to be_invalid

      source.poll.update!(school_managed: false)
      replacement_poll.update!(status: :in_progress)
      expect(build(:poll_session, poll: replacement_poll, classroom: source.classroom,
                                  operator: source.operator, replacement_of: source)).to be_invalid
    end

    it "allows a schoolwide replacement on the same in-progress Poll" do
      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, status: :in_progress, started_at: Time.current)
      source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                     status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)

      replacement = build(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                         replacement_of: source)

      expect(replacement).to be_valid
    end

    it "allows a closed schoolwide source and identifies only the leaf as current" do
      school = create(:school)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, status: :in_progress, started_at: Time.current)
      source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                     status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
      replacement = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                          replacement_of: source)

      expect(poll.current_poll_sessions).to contain_exactly(replacement)
      expect(poll.poll_sessions).to contain_exactly(source, replacement)
    end

    it "allows a chain but only one direct replacement and prevents changing the source" do
      first = stopped_session
      second = create(:poll_session, poll: first.poll, classroom: first.classroom,
                                     operator: first.operator, replacement_of: first)
      second.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      expect(build(:poll_session, poll: first.poll, classroom: first.classroom,
                                  operator: first.operator, replacement_of: first)).to be_invalid

      third = create(:poll_session, poll: second.poll, classroom: second.classroom,
                                    operator: second.operator, replacement_of: second)
      expect(third.replacement_of).to eq(second)

      other_source = stopped_session
      expect(third.update(replacement_of: other_source)).to be(false)
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
