require "rails_helper"

RSpec.describe Polls::StartSession do
  def create_startable_session(operator: nil, students: [[3, "김삼"], [1, "김일"], [2, "김이"]])
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    classroom = create(:classroom, school: school, teacher: teacher)
    students.each { |number, name| create(:student, classroom: classroom, number: number, name: name) }
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 2)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator || teacher
    )

    [poll_session, teacher]
  end

  describe "successful start" do
    it "creates the complete PollSession execution snapshot" do
      poll_session, actor = create_startable_session

      result = described_class.new(actor: actor, poll_session: poll_session).call

      expect(result).to be_success
      expect(result.poll_session).to eq(poll_session)
      expect(poll_session.reload).to have_attributes(
        status: "in_progress",
        operator: actor,
        operator_name_snapshot: actor.name
      )
      expect(poll_session.started_at).to be_present
      expect(poll_session.poll_participants.count).to eq(3)
      expect(poll_session.poll_progress).to be_present
      expect(poll_session.poll_option_tallies.count).to eq(poll_session.poll.poll_options.count)
      expect(poll_session.poll_contest_tallies.count).to eq(poll_session.poll.poll_contests.count)
      expect(poll_session.poll_events.where(event_type: "poll_started").count).to eq(1)
      expect(PollParticipation.where(poll_participant: poll_session.poll_participants)).to be_empty
    end

    it "uses an edited replacement roster without resnapshotting current Classroom Students" do
      source, actor = create_startable_session(students: [[1, "현재 학생"]])
      source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                source_participant_slot: nil, number: 1, name: "이전 학생")
      replacement = Polls::RevoteSession.new(actor: actor, poll_session: source).call.poll_session
      replacement.poll_participants.first.update!(number: 7, name: "편집 학생")
      source_poll_attributes = source.poll.attributes.slice("title", "kind", "status", "started_at", "closed_at")
      source.classroom.students.update_all(name: "변경된 Classroom 학생")

      result = described_class.new(actor: actor, poll_session: replacement).call

      expect(result).to be_success
      expect(replacement.poll_participants.pluck(:number, :name)).to eq([[7, "편집 학생"]])
      expect(replacement.poll_progress.current_poll_participant.name).to eq("편집 학생")
      expect(replacement.poll).not_to eq(source.poll)
      expect(source.poll.reload.attributes.slice("title", "kind", "status", "started_at", "closed_at")).to eq(source_poll_attributes)
    end

    it "rejects a replacement without a roster or with other execution records" do
      source, actor = create_startable_session
      source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      replacement = create(:poll_session, poll: source.poll, classroom: source.classroom,
                                          operator: actor, replacement_of: source)

      expect(described_class.new(actor: actor, poll_session: replacement).call).not_to be_success

      participant = create(:poll_participant, poll: source.poll, poll_session: replacement,
                                              source_participant_slot: nil)
      create(:poll_participation, poll_participant: participant)
      expect(described_class.new(actor: actor, poll_session: replacement).call).not_to be_success
    end

    it "snapshots active Students in number order and excludes inactive Students" do
      poll_session, actor = create_startable_session
      create(:student, classroom: poll_session.classroom, number: 4, name: "비활성", active: false)

      described_class.new(actor: actor, poll_session: poll_session).call

      expect(poll_session.poll_participants.order(:number).pluck(:number, :name)).to eq(
        [[1, "김일"], [2, "김이"], [3, "김삼"]]
      )
      expect(poll_session.poll_participants).to all(have_attributes(source_participant_slot_id: nil))
    end

    it "keeps the snapshot after Student data changes" do
      poll_session, actor = create_startable_session(students: [[1, "시작 이름"]])
      student = poll_session.classroom.students.first

      described_class.new(actor: actor, poll_session: poll_session).call
      student.update!(number: 9, name: "변경 이름", active: false)

      expect(poll_session.poll_participants.first).to have_attributes(number: 1, name: "시작 이름")
    end

    it "does not create ParticipantGroup, ParticipantSlot, or PollParticipation records" do
      poll_session, actor = create_startable_session
      counts = [ParticipantGroup.count, ParticipantSlot.count, PollParticipation.count]

      described_class.new(actor: actor, poll_session: poll_session).call

      expect([ParticipantGroup.count, ParticipantSlot.count, PollParticipation.count]).to eq(counts)
    end
  end

  describe "progress, tallies, and event" do
    it "creates progress with the legacy initial semantics and shared start time" do
      poll_session, actor = create_startable_session

      described_class.new(actor: actor, poll_session: poll_session).call
      poll_session.reload
      progress = poll_session.poll_progress
      first_participant = poll_session.poll_participants.order(:number, :id).first

      expect(progress).to have_attributes(
        poll: poll_session.poll,
        poll_session: poll_session,
        current_poll_participant: first_participant,
        status: "active",
        ballot_status: "ballot_locked",
        closed_at: nil
      )
      expect(progress.started_at).to eq(poll_session.reload.started_at)
    end

    it "creates zeroed tallies for every option and contest alongside legacy tallies" do
      poll_session, actor = create_startable_session
      poll = poll_session.poll
      create(:poll_option_tally, poll: poll, poll_option: poll.poll_options.first)
      create(:poll_contest_tally, poll: poll, poll_contest: poll.poll_contests.first)

      result = described_class.new(actor: actor, poll_session: poll_session).call

      expect(result).to be_success
      expect(poll_session.poll_option_tallies.map(&:poll_option)).to match_array(poll.poll_options)
      expect(poll_session.poll_option_tallies).to all(have_attributes(poll: poll, votes_count: 0))
      expect(poll_session.poll_contest_tallies.map(&:poll_contest)).to match_array(poll.poll_contests)
      expect(poll_session.poll_contest_tallies).to all(have_attributes(poll: poll, abstentions_count: 0))
    end

    it "records a privacy-safe poll_started event for the PollSession" do
      poll_session, actor = create_startable_session

      described_class.new(actor: actor, poll_session: poll_session).call
      event = poll_session.poll_events.last

      expect(event).to have_attributes(
        poll: poll_session.poll,
        poll_session: poll_session,
        actor: actor,
        poll_participant: nil,
        event_type: "poll_started",
        occurred_at: poll_session.reload.started_at
      )
      expect(event.details).to include(
        "participant_count" => 3,
        "classroom_name_snapshot" => poll_session.classroom_name_snapshot
      )
      expect(event.details.keys).not_to include("poll_option_id", "poll_option_name", "poll_option_number")
    end
  end

  describe "Poll definition invariants" do
    it "does not change Poll lifecycle, ownership, school, or legacy source" do
      poll_session, actor = create_startable_session
      poll = poll_session.poll
      original_attributes = poll.attributes.slice(
        "status", "archived_at", "user_id", "school_id", "participant_group_id"
      )

      described_class.new(actor: actor, poll_session: poll_session).call

      expect(poll.reload.attributes.slice(*original_attributes.keys)).to eq(original_attributes)
    end
  end

  describe "actor authorization" do
    it "allows the Classroom teacher" do
      poll_session, teacher = create_startable_session

      expect(described_class.new(actor: teacher, poll_session: poll_session).call).to be_success
    end

    it "allows a same-school manager and records the actual operator" do
      poll_session, classroom_teacher = create_startable_session
      manager = create(:user)
      create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

      result = described_class.new(actor: manager, poll_session: poll_session).call

      expect(result).to be_success
      expect(poll_session.reload).to have_attributes(operator: manager, operator_name_snapshot: manager.name)
      expect(poll_session.classroom.reload.teacher).to eq(classroom_teacher)
    end

    it "allows a global admin and records the actual operator" do
      poll_session, classroom_teacher = create_startable_session
      admin = create(:user, :admin)

      result = described_class.new(actor: admin, poll_session: poll_session).call

      expect(result).to be_success
      expect(poll_session.reload).to have_attributes(operator: admin, operator_name_snapshot: admin.name)
      expect(poll_session.classroom.reload.teacher).to eq(classroom_teacher)
    end

    it "rejects another teacher, another-school manager, membershipless teacher, and nil actor" do
      actors = []
      poll_session, = create_startable_session
      other_teacher = create(:user)
      create(:school_membership, school: poll_session.classroom.school, user: other_teacher)
      actors << other_teacher
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)
      actors << other_manager
      actors << create(:user)
      actors << nil

      actors.each do |actor|
        result = described_class.new(actor: actor, poll_session: poll_session).call
        expect(result).not_to be_success
        expect(poll_session.reload).to be_draft
      end
    end
  end

  describe "Classroom and Student eligibility" do
    it "rejects an inactive Classroom" do
      poll_session, actor = create_startable_session
      poll_session.classroom.update!(active: false)

      expect(described_class.new(actor: actor, poll_session: poll_session).call).not_to be_success
    end

    it "rejects a Classroom with no active Students" do
      poll_session, actor = create_startable_session
      poll_session.classroom.students.update_all(active: false)

      result = described_class.new(actor: actor, poll_session: poll_session).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 대상 학생이 없습니다.", "활성 학생이 1명 이상이어야 합니다.")
      expect(poll_session.reload).to be_draft
      expect(poll_session.poll_participants).to be_empty
      expect(poll_session.poll_progress).to be_nil
      expect(poll_session.poll_option_tallies).to be_empty

      create(:student, classroom: poll_session.classroom, number: 4, name: "등록 학생")
      expect(described_class.new(actor: actor, poll_session: poll_session).call).to be_success
    end

    it "rejects a corrupted cross-school PollSession" do
      poll_session, actor = create_startable_session
      other_teacher = create(:user)
      other_school = create(:school)
      create(:school_membership, school: other_school, user: other_teacher)
      other_teacher.reload
      other_classroom = create(:classroom, school: other_school, teacher: other_teacher)
      create(:student, classroom: other_classroom)
      poll_session.update_column(:classroom_id, other_classroom.id)

      expect(described_class.new(actor: actor, poll_session: poll_session.reload).call).not_to be_success
    end
  end

  describe "definition readiness" do
    it "rejects a Poll without contests" do
      poll_session, actor = create_startable_session
      poll_session.poll.poll_contests.destroy_all

      expect(described_class.new(actor: actor, poll_session: poll_session).call).not_to be_success
    end

    it "rejects a contest without options and a single-option definition" do
      poll_session, actor = create_startable_session
      poll_session.poll.poll_options.destroy_all
      expect(described_class.new(actor: actor, poll_session: poll_session).call).not_to be_success

      create(:poll_option, poll: poll_session.poll, poll_contest: poll_session.poll.default_poll_contest)
      expect(described_class.new(actor: actor, poll_session: poll_session).call).not_to be_success
    end

    it "starts without a ParticipantGroup when contests and options are ready" do
      poll_session, actor = create_startable_session

      expect(poll_session.poll.participant_group).to be_nil
      expect(described_class.new(actor: actor, poll_session: poll_session).call).to be_success
    end
  end

  describe "state and duplicate protection" do
    it "rejects in_progress, closed, and stopped PollSessions without creating records" do
      %i[in_progress closed stopped].each do |status|
        poll_session, actor = create_startable_session
        poll_session.update!(
          status: status,
          started_at: 1.hour.ago,
          closed_at: (Time.current if status == :closed),
          stopped_at: (Time.current if status == :stopped)
        )
        result = described_class.new(actor: actor, poll_session: poll_session).call

        expect(result).not_to be_success
        expect(poll_session.poll_participants).to be_empty
        expect(poll_session.poll_progress).to be_nil
        expect(poll_session.poll_events).to be_empty
      end
    end

    it "fails a second call without duplicating execution records" do
      poll_session, actor = create_startable_session
      expect(described_class.new(actor: actor, poll_session: poll_session).call).to be_success
      counts = execution_counts(poll_session.reload)

      second_result = described_class.new(actor: actor, poll_session: poll_session).call

      expect(second_result).not_to be_success
      expect(execution_counts(poll_session.reload)).to eq(counts)
    end
  end

  describe "transaction rollback" do
    it "rolls back all records and operator changes when start event creation fails" do
      poll_session, original_operator = create_startable_session
      admin = create(:user, :admin)
      original_snapshot = poll_session.operator_name_snapshot
      invalid_event = PollEvent.new
      invalid_event.errors.add(:base, "forced failure")
      allow(PollEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_event))

      result = described_class.new(actor: admin, poll_session: poll_session).call

      expect(result).not_to be_success
      expect(execution_counts(poll_session.reload)).to eq([0, 0, 0, 0, 0])
      expect(poll_session).to have_attributes(
        status: "draft",
        started_at: nil,
        operator: original_operator,
        operator_name_snapshot: original_snapshot
      )
    end
  end

  describe "legacy isolation" do
    it "does not alter an existing ParticipantGroup Poll or its roster" do
      legacy_poll = create(:poll)
      legacy_attributes = legacy_poll.attributes
      group_count = ParticipantGroup.count
      slot_count = ParticipantSlot.count
      poll_session, actor = create_startable_session

      expect(described_class.new(actor: actor, poll_session: poll_session).call).to be_success
      expect(legacy_poll.reload.attributes).to eq(legacy_attributes)
      expect(ParticipantGroup.count).to eq(group_count)
      expect(ParticipantSlot.count).to eq(slot_count)
    end
  end

  def execution_counts(poll_session)
    [
      poll_session.poll_participants.count,
      poll_session.poll_progress.present? ? 1 : 0,
      poll_session.poll_option_tallies.count,
      poll_session.poll_contest_tallies.count,
      poll_session.poll_events.count
    ]
  end
end
