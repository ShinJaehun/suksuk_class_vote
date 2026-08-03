module Elections
  class ConvertLegacyElectionToClassrooms
    class ConversionFailed < StandardError; end

    Result = Struct.new(
      :success?,
      :errors,
      :applied,
      :already_converted,
      :report,
      keyword_init: true
    ) do
      def applied?
        applied
      end

      def already_converted?
        already_converted
      end

      def error_message
        errors.join("\n")
      end

      def election_id
        report[:election_id]
      end

      def session_count
        report[:session_count]
      end

      def participant_group_count
        report[:participant_group_count]
      end

      def classroom_count
        report[:classroom_count]
      end

      def student_count
        report[:student_count]
      end

      def membership_create_count
        report[:membership_create_count]
      end

      def preserved_counts
        report[:preserved_counts]
      end
    end

    def initialize(election:, school_year:, apply: false)
      @election = election
      @school_year = school_year
      @apply = apply
    end

    def call
      plan = build_plan
      return result_for(plan) unless plan[:convertible]
      return result_for(plan) unless apply

      apply_plan!
    rescue ActiveRecord::ActiveRecordError, ConversionFailed => error
      failure([error.message], report: plan&.fetch(:report, nil))
    end

    private

    attr_reader :election, :school_year, :apply

    def build_plan
      errors = []
      errors << "Election을 찾을 수 없습니다." if election.blank?
      errors << "school_year는 양의 정수여야 합니다." unless positive_integer?(school_year)
      return { convertible: false, already_converted: false, errors: errors, report: empty_report } if election.blank?

      sessions = election.election_sessions.order(:id).to_a
      legacy_sessions = sessions.select { |session| session.participant_group_id.present? && session.classroom_id.nil? }
      classroom_sessions = sessions.select { |session| session.classroom_id.present? && session.participant_group_id.nil? }
      invalid_sessions = sessions - legacy_sessions - classroom_sessions

      errors << "Election에 school이 없습니다." if election.school.blank?
      errors << "ElectionSession이 없습니다." if sessions.empty?
      errors << "exactly-one source를 만족하지 않는 ElectionSession이 있습니다." if invalid_sessions.any?
      errors << "legacy와 Classroom 기반 ElectionSession이 섞여 있습니다." if legacy_sessions.any? && classroom_sessions.any?

      already_converted = sessions.any? && classroom_sessions.size == sessions.size
      groups = legacy_sessions.map(&:participant_group).compact.uniq(&:id).sort_by(&:id)
      validate_groups(groups, errors) if errors.empty? && !already_converted

      report = build_report(sessions, groups, errors)
      {
        convertible: errors.empty? && !already_converted,
        already_converted: already_converted,
        errors: errors,
        report: report
      }
    end

    def validate_groups(groups, errors)
      errors << "변환할 legacy ParticipantGroup이 없습니다." if groups.empty?
      identities = Hash.new { |hash, key| hash[key] = [] }
      teacher_ids = Hash.new { |hash, key| hash[key] = [] }

      groups.each do |group|
        label = group.class_label.to_s.strip
        slots = group.participant_slots.order(:number).to_a

        errors << "ParticipantGroup #{group.id}: Election과 학교가 다릅니다." if group.school_id != election.school_id
        errors << "ParticipantGroup #{group.id}: school_election 명단이 아닙니다." unless group.school_election?
        errors << "ParticipantGroup #{group.id}: teacher가 없습니다." if group.user.blank?
        errors << "ParticipantGroup #{group.id}: teacher 역할이 아닙니다." if group.user.present? && !group.user.teacher?
        errors << "ParticipantGroup #{group.id}: grade가 유효하지 않습니다." unless positive_integer?(group.grade)
        errors << "ParticipantGroup #{group.id}: class_label이 없습니다." if label.blank?
        errors << "ParticipantGroup #{group.id}: class_label이 30자를 초과합니다." if label.length > 30
        errors << "ParticipantGroup #{group.id}: ParticipantSlot 명단이 없습니다." if slots.empty?
        validate_slots(group, slots, errors)
        validate_membership(group, errors)
        errors << "teacher #{group.user_id}: 이미 active Classroom에 배정되어 있습니다." if group.user&.active_classroom.present?

        identities[[group.school_id, school_year.to_i, group.grade, label]] << group.id
        teacher_ids[group.user_id] << group.id if group.user_id.present?
      end

      identities.each do |identity, group_ids|
        next if group_ids.one?

        errors << "ParticipantGroup #{group_ids.join(', ')}: 같은 Classroom 식별값이 중복됩니다 (#{identity.last})."
      end

      teacher_ids.each do |teacher_id, group_ids|
        next if group_ids.one?

        errors << "teacher #{teacher_id}: 여러 active Classroom에 동시에 배정할 수 없습니다 (ParticipantGroup #{group_ids.join(', ')})."
      end

      target_identities = identities.keys
      existing = Classroom.where(school_id: election.school_id, school_year: school_year.to_i)
        .where(grade: target_identities.map { |identity| identity[2] }.compact)
        .where(class_label: target_identities.map(&:last))
      existing.each do |classroom|
        identity = [classroom.school_id, classroom.school_year, classroom.grade, classroom.class_label]
        next unless identities.key?(identity)

        errors << "Classroom #{classroom.id}: 대상 Classroom이 이미 존재합니다."
      end
    end

    def validate_slots(group, slots, errors)
      duplicate_numbers = slots.group_by(&:number).select { |_number, entries| entries.many? }.keys
      errors << "ParticipantGroup #{group.id}: Student 번호가 중복됩니다 (#{duplicate_numbers.join(', ')})." if duplicate_numbers.any?

      slots.each do |slot|
        errors << "ParticipantSlot #{slot.id}: number가 유효하지 않습니다." unless positive_integer?(slot.number)
        errors << "ParticipantSlot #{slot.id}: name이 없습니다." if slot.name.blank?
      end
    end

    def validate_membership(group, errors)
      membership = group.user&.school_membership
      return if membership.blank? || membership.school_id == election.school_id

      errors << "teacher #{group.user_id}: 다른 학교 SchoolMembership에 속해 있습니다."
    end

    def apply_plan!
      applied_report = nil

      Election.transaction do
        election.with_lock do
          locked_plan = build_plan
          raise ConversionFailed, locked_plan[:errors].join("\n") unless locked_plan[:convertible]

          before_invariants = invariant_snapshot
          groups = legacy_groups
          ensure_memberships!(groups)
          classrooms_by_group_id = create_classrooms!(groups)
          connect_sessions!(classrooms_by_group_id)
          election.election_sessions.reset

          after_invariants = invariant_snapshot
          raise ConversionFailed, "선거 기록 invariant가 변경되었습니다." unless before_invariants == after_invariants

          applied_report = locked_plan[:report]
        end
      end

      success(applied_report, applied: true)
    end

    def ensure_memberships!(groups)
      groups.each do |group|
        next if group.user.school_membership

        group.user.create_school_membership!(school: election.school, role: :member)
        group.user.association(:school).reset
      end
    end

    def create_classrooms!(groups)
      groups.each_with_object({}) do |group, classrooms|
        classroom = Classroom.create!(
          school: election.school,
          school_year: school_year.to_i,
          grade: group.grade,
          class_label: group.class_label,
          name: classroom_name(group.grade, group.class_label),
          teacher: group.user,
          active: true
        )

        group.participant_slots.order(:number).each do |slot|
          Student.create!(classroom: classroom, number: slot.number, name: slot.name, active: true)
        end
        classrooms[group.id] = classroom
      end
    end

    def connect_sessions!(classrooms_by_group_id)
      now = Time.current
      classrooms_by_group_id.each do |group_id, classroom|
        election.election_sessions
          .where(participant_group_id: group_id, classroom_id: nil)
          .update_all(classroom_id: classroom.id, participant_group_id: nil, updated_at: now)
      end
    end

    def invariant_snapshot
      session_ids = election.election_sessions.order(:id).pluck(:id)
      voter_scope = ElectionVoter.where(election_session_id: session_ids)
      voter_ids = voter_scope.order(:id).pluck(:id)

      {
        sessions: election.election_sessions.order(:id).pluck(
          :id,
          :election_id,
          :teacher_id,
          :status,
          :operation_mode,
          :started_at,
          :stopped_at,
          :closed_at,
          :hidden_from_teacher_at,
          :created_at
        ),
        session_voter_counts: voter_scope.group(:election_session_id).count.sort.to_h,
        voters: voter_ids,
        participations: ElectionParticipation.where(election_voter_id: voter_ids).order(:id).pluck(:id),
        progresses: ElectionProgress.where(election_session_id: session_ids).order(:id).pluck(:id),
        candidate_tallies: ElectionCandidateTally.where(election_session_id: session_ids).order(:id).pluck(:id),
        contest_tallies: ElectionContestTally.where(election_session_id: session_ids).order(:id).pluck(:id),
        events: ElectionEvent.where(election_session_id: session_ids).order(:id).pluck(:id)
      }
    end

    def build_report(sessions, groups, errors)
      session_ids = sessions.map(&:id)
      voter_ids = ElectionVoter.where(election_session_id: session_ids).pluck(:id)
      memberships = groups.map(&:user).compact.map(&:school_membership)
      preserved_counts = {
        voters: voter_ids.size,
        participations: ElectionParticipation.where(election_voter_id: voter_ids).count,
        progresses: ElectionProgress.where(election_session_id: session_ids).count,
        candidate_tallies: ElectionCandidateTally.where(election_session_id: session_ids).count,
        contest_tallies: ElectionContestTally.where(election_session_id: session_ids).count,
        events: ElectionEvent.where(election_session_id: session_ids).count
      }

      {
        election_id: election&.id,
        election_title: election&.title,
        school: election&.school&.name,
        session_count: sessions.size,
        participant_group_count: groups.size,
        classroom_count: groups.size,
        student_count: groups.sum { |group| group.participant_slots.size },
        membership_create_count: memberships.count(&:nil?),
        stopped_session_count: sessions.count(&:stopped?),
        closed_session_count: sessions.count(&:closed?),
        preserved_counts: preserved_counts,
        groups: groups.map do |group|
          {
            grade: group.grade,
            class_label: group.class_label,
            teacher: group.user&.name.presence || group.user&.email,
            student_count: group.participant_slots.size,
            session_count: sessions.count { |session| session.participant_group_id == group.id }
          }
        end,
        errors: errors
      }
    end

    def legacy_groups
      election.election_sessions.where.not(participant_group_id: nil)
        .includes(participant_group: %i[user participant_slots])
        .map(&:participant_group)
        .uniq(&:id)
        .sort_by(&:id)
    end

    def result_for(plan)
      return failure(plan[:errors], report: plan[:report]) if plan[:errors].any?
      return success(plan[:report], applied: false, already_converted: true) if plan[:already_converted]

      success(plan[:report], applied: false)
    end

    def success(report, applied:, already_converted: false)
      Result.new(
        success?: true,
        errors: [],
        applied: applied,
        already_converted: already_converted,
        report: report
      )
    end

    def failure(errors, report: nil)
      Result.new(
        success?: false,
        errors: Array(errors),
        applied: false,
        already_converted: false,
        report: report || empty_report
      )
    end

    def empty_report
      {
        election_id: election&.id,
        election_title: election&.title,
        school: election&.school&.name,
        session_count: 0,
        participant_group_count: 0,
        classroom_count: 0,
        student_count: 0,
        membership_create_count: 0,
        stopped_session_count: 0,
        closed_session_count: 0,
        preserved_counts: {},
        groups: [],
        errors: []
      }
    end

    def classroom_name(grade, class_label)
      label = class_label.to_s
      formatted_label = label.match?(/\A\d+\z/) ? "#{label}반" : label
      "#{grade}학년 #{formatted_label}"
    end

    def positive_integer?(value)
      value.to_s.match?(/\A[1-9]\d*\z/)
    end
  end
end
