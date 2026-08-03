require "rails_helper"

RSpec.describe Elections::ConvertLegacyElectionToClassrooms do
  describe "#call" do
    it "returns a dry-run report without changing any rows" do
      election = create(:election)
      group = create_legacy_group(election: election, class_label: "1", slot_names: %w[한나 두나])
      session = create(:election_session, election: election, teacher: group.user, participant_group: group)
      before_counts = conversion_counts

      result = convert(election, apply: false)

      expect(result).to be_success
      expect(result).not_to be_applied
      expect(result.report).to include(
        election_id: election.id,
        session_count: 1,
        participant_group_count: 1,
        classroom_count: 1,
        student_count: 2,
        membership_create_count: 1
      )
      expect(conversion_counts).to eq(before_counts)
      expect(session.reload).to have_attributes(participant_group_id: group.id, classroom_id: nil)
    end

    it "creates one Classroom per group and moves only the selected Election sessions" do
      election = create(:election)
      first_group = create_legacy_group(election: election, grade: 4, class_label: "1", slot_names: %w[가 나])
      second_group = create_legacy_group(election: election, grade: 5, class_label: "13", slot_names: %w[다 라 마])
      first_session = create(:election_session, election: election, teacher: first_group.user, participant_group: first_group)
      second_session = create(:election_session, election: election, teacher: second_group.user, participant_group: second_group)
      other_election = create(:election)
      other_group = create_legacy_group(election: other_election, class_label: "9", slot_names: %w[기타])
      other_session = create(:election_session, election: other_election, teacher: other_group.user, participant_group: other_group)

      result = convert(election, apply: true)

      expect(result).to be_success
      expect(result).to be_applied
      expect(result).not_to be_already_converted
      expect(Classroom.where(school: election.school, school_year: 2026).count).to eq(2)
      first_classroom = Classroom.find_by!(school: election.school, school_year: 2026, grade: 4, class_label: "1")
      second_classroom = Classroom.find_by!(school: election.school, school_year: 2026, grade: 5, class_label: "13")
      expect(first_classroom).to have_attributes(teacher_id: first_group.user_id, active: true, name: "4학년 1반")
      expect(second_classroom).to have_attributes(teacher_id: second_group.user_id, active: true, name: "5학년 13반")
      expect(first_classroom.students.order(:number).pluck(:number, :name, :active)).to eq([[1, "가", true], [2, "나", true]])
      expect(second_classroom.students.order(:number).pluck(:number, :name)).to eq([[1, "다"], [2, "라"], [3, "마"]])
      expect(first_session.reload).to have_attributes(id: first_session.id, classroom_id: first_classroom.id, participant_group_id: nil)
      expect(second_session.reload).to have_attributes(id: second_session.id, classroom_id: second_classroom.id, participant_group_id: nil)
      expect(SchoolMembership.where(school: election.school, user: [first_group.user, second_group.user], role: :member).count).to eq(2)
      expect(other_session.reload).to have_attributes(participant_group_id: other_group.id, classroom_id: nil)
    end

    it "preserves a character class label without adding a suffix" do
      election = create(:election)
      group = create_legacy_group(election: election, grade: 6, class_label: "생활교육실", slot_names: %w[학생])
      create(:election_session, election: election, teacher: group.user, participant_group: group)

      expect(convert(election, apply: true)).to be_success

      classroom = Classroom.find_by!(school: election.school, school_year: 2026, grade: 6)
      expect(classroom).to have_attributes(class_label: "생활교육실", name: "6학년 생활교육실")
    end

    it "connects stopped and replacement sessions to one Classroom while preserving result rows" do
      election = create(:election, status: :in_progress)
      group = create_legacy_group(election: election, class_label: "1", slot_names: %w[현재명단1 현재명단2])
      stopped = create(:election_session, election: election, teacher: group.user, participant_group: group, status: :stopped)
      closed = create(:election_session, election: election, teacher: group.user, participant_group: group, status: :closed)
      stopped_rows = create_result_rows(stopped, group, voter_name: "중단snapshot")
      closed_rows = create_result_rows(closed, group, voter_name: "재투표snapshot")
      preserved_ids = result_ids_for(election)

      result = convert(election, apply: true)

      expect(result).to be_success
      expect(stopped.reload).to have_attributes(status: "stopped", participant_group_id: nil)
      expect(closed.reload).to have_attributes(status: "closed", participant_group_id: nil, classroom_id: stopped.classroom_id)
      expect(result_ids_for(election)).to eq(preserved_ids)
      expect(stopped_rows.values).to all(be_persisted)
      expect(closed_rows.values).to all(be_persisted)
      expect(stopped.classroom.students.count).to eq(2)
      expect(stopped.election_voters.pluck(:name)).to eq(["중단snapshot"])
      expect(closed.election_voters.pluck(:name)).to eq(["재투표snapshot"])
    end

    it "reuses a same-school membership" do
      election = create(:election)
      teacher = create(:user)
      membership = create(:school_membership, school: election.school, user: teacher, role: :manager)
      group = create_legacy_group(election: election, teacher: teacher, class_label: "1", slot_names: %w[학생])
      create(:election_session, election: election, teacher: teacher, participant_group: group)

      expect { convert(election, apply: true) }.not_to change(SchoolMembership, :count)
      expect(membership.reload).to be_manager
    end

    it "rejects a teacher membership from another school without changing data" do
      election = create(:election)
      teacher = create(:user)
      create(:school_membership, school: create(:school), user: teacher)
      group = create_legacy_group(election: election, teacher: teacher, class_label: "1", slot_names: %w[학생])
      session = create(:election_session, election: election, teacher: teacher, participant_group: group)
      before_counts = conversion_counts

      result = convert(election, apply: true)

      expect(result).not_to be_success
      expect(result.error_message).to include("다른 학교 SchoolMembership")
      expect(conversion_counts).to eq(before_counts)
      expect(session.reload.classroom_id).to be_nil
    end

    it "rejects an existing target Classroom" do
      election = create(:election)
      group = create_legacy_group(election: election, class_label: "1", slot_names: %w[학생])
      create(:election_session, election: election, teacher: group.user, participant_group: group)
      create(:classroom, school: election.school, school_year: 2026, grade: group.grade, class_label: group.class_label)

      result = convert(election, apply: true)

      expect(result).not_to be_success
      expect(result.error_message).to include("대상 Classroom이 이미 존재")
    end

    it "rejects a group from another school and a missing raw class label" do
      election = create(:election)
      other_school_group = create(
        :participant_group,
        :school_election,
        school: create(:school),
        user: create(:user),
        class_label: "1"
      )
      create(:participant_slot, participant_group: other_school_group)
      create(:election_session, election: election, teacher: other_school_group.user, participant_group: other_school_group)
      missing_label_group = create_legacy_group(election: election, class_label: "2", slot_names: %w[학생])
      create(:election_session, election: election, teacher: missing_label_group.user, participant_group: missing_label_group, status: :closed)
      missing_label_group.update_column(:class_label, nil)

      result = convert(election, apply: false)

      expect(result).not_to be_success
      expect(result.error_message).to include("Election과 학교가 다릅니다")
      expect(result.error_message).to include("class_label이 없습니다")
    end

    it "rejects mixed legacy and Classroom session sources" do
      election = create(:election)
      group = create_legacy_group(election: election, class_label: "1", slot_names: %w[학생])
      create(:election_session, election: election, teacher: group.user, participant_group: group)
      classroom = create(:classroom, :with_teacher, school: election.school, class_label: "2")
      create(:election_session, election: election, teacher: classroom.teacher, participant_group: nil, classroom: classroom)

      result = convert(election, apply: false)

      expect(result).not_to be_success
      expect(result.error_message).to include("섞여 있습니다")
    end

    it "rejects an invalid school year" do
      election = create(:election)
      group = create_legacy_group(election: election, class_label: "1", slot_names: %w[학생])
      create(:election_session, election: election, teacher: group.user, participant_group: group)

      result = described_class.new(election: election, school_year: "2026x", apply: false).call

      expect(result).not_to be_success
      expect(result.error_message).to include("school_year")
    end

    it "rolls back memberships, Classrooms, Students, and source changes on an apply failure" do
      election = create(:election)
      first_group = create_legacy_group(election: election, class_label: "1", slot_names: %w[가])
      second_group = create_legacy_group(election: election, class_label: "2", slot_names: %w[나])
      sessions = [
        create(:election_session, election: election, teacher: first_group.user, participant_group: first_group),
        create(:election_session, election: election, teacher: second_group.user, participant_group: second_group)
      ]
      before_counts = conversion_counts
      allow(Classroom).to receive(:create!).and_wrap_original do |method, **attributes|
        raise ActiveRecord::RecordInvalid.new(Classroom.new) if attributes[:class_label] == "2"

        method.call(**attributes)
      end

      result = convert(election, apply: true)

      expect(result).not_to be_success
      expect(conversion_counts).to eq(before_counts)
      expect(sessions.map { |session| session.reload.attributes.slice("participant_group_id", "classroom_id") }).to eq([
        { "participant_group_id" => first_group.id, "classroom_id" => nil },
        { "participant_group_id" => second_group.id, "classroom_id" => nil }
      ])
    end

    it "returns an already-converted no-op when every session uses Classroom" do
      election = create(:election)
      classroom = create(:classroom, :with_teacher, school: election.school)
      create(:student, classroom: classroom)
      create(:election_session, election: election, teacher: classroom.teacher, participant_group: nil, classroom: classroom)
      before_counts = conversion_counts

      result = convert(election, apply: true)

      expect(result).to be_success
      expect(result).to be_already_converted
      expect(result).not_to be_applied
      expect(conversion_counts).to eq(before_counts)
    end
  end

  def convert(election, apply:)
    described_class.new(election: election, school_year: 2026, apply: apply).call
  end

  def create_legacy_group(election:, class_label:, slot_names:, grade: 4, teacher: create(:user))
    group = create(
      :participant_group,
      :school_election,
      school: election.school,
      user: teacher,
      grade: grade,
      class_label: class_label
    )
    slot_names.each_with_index do |name, index|
      create(:participant_slot, participant_group: group, number: index + 1, name: name)
    end
    group
  end

  def create_result_rows(session, group, voter_name:)
    slot = group.participant_slots.first
    voter = create(
      :election_voter,
      election_session: session,
      source_participant_slot: slot,
      number: slot.number,
      name: voter_name,
      position: 1
    )
    participation = create(:election_participation, election_voter: voter, status: :completed)
    progress = create(:election_progress, election_session: session, current_election_voter: voter)
    contest = session.election.election_contests.first || create(:election_contest, election: session.election)
    candidate = contest.election_candidates.first || create(:election_candidate, election_contest: contest)
    candidate_tally = create(:election_candidate_tally, election_session: session, election_contest: contest, election_candidate: candidate)
    contest_tally = create(:election_contest_tally, election_session: session, election_contest: contest)
    event = create(:election_event, election_session: session, election_voter: voter, actor: session.teacher)

    { voter: voter, participation: participation, progress: progress, candidate_tally: candidate_tally, contest_tally: contest_tally, event: event }
  end

  def result_ids_for(election)
    session_ids = election.election_session_ids.sort
    voter_ids = ElectionVoter.where(election_session_id: session_ids).order(:id).pluck(:id)
    {
      sessions: election.election_sessions.order(:id).pluck(:id, :status),
      voters: voter_ids,
      participations: ElectionParticipation.where(election_voter_id: voter_ids).order(:id).pluck(:id),
      progresses: ElectionProgress.where(election_session_id: session_ids).order(:id).pluck(:id),
      candidate_tallies: ElectionCandidateTally.where(election_session_id: session_ids).order(:id).pluck(:id),
      contest_tallies: ElectionContestTally.where(election_session_id: session_ids).order(:id).pluck(:id),
      events: ElectionEvent.where(election_session_id: session_ids).order(:id).pluck(:id)
    }
  end

  def conversion_counts
    {
      memberships: SchoolMembership.count,
      classrooms: Classroom.count,
      students: Student.count,
      sessions: ElectionSession.count,
      groups: ParticipantGroup.count,
      slots: ParticipantSlot.count,
      voters: ElectionVoter.count,
      participations: ElectionParticipation.count,
      progresses: ElectionProgress.count,
      candidate_tallies: ElectionCandidateTally.count,
      contest_tallies: ElectionContestTally.count,
      events: ElectionEvent.count
    }
  end
end
