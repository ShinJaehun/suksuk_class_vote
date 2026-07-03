module Admin
  class ElectionRostersController < BaseController
    before_action :set_participant_group, only: %i[edit update destroy edit_students update_students]
    before_action :set_teachers, only: %i[new create edit update new_bulk bulk_create]

    def index
      @schools = School.order(:name)
      @school = selected_school
      if params[:school_id].present? && @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 찾을 수 없습니다."
        return
      end

      @participant_groups = if @school.present?
        @school.participant_groups.school_election.includes(:user, :participant_slots).order(:grade, :class_label, :name)
      else
        ParticipantGroup.none
      end
      assigned_sessions = ElectionSession.roster_locking
        .where(participant_group_id: @participant_groups.select(:id))
        .includes(:election)
        .to_a
      @assigned_participant_group_ids = assigned_sessions.map(&:participant_group_id).uniq
      @assigned_elections_by_participant_group_id = assigned_sessions
        .group_by(&:participant_group_id)
        .transform_values { |sessions| sessions.map(&:election).uniq(&:id) }
    end

    def new
      @school = School.find_by(id: params[:school_id])
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @participant_group = @school.participant_groups.build(purpose: :school_election)
    end

    def new_bulk
      @school = School.find_by(id: params[:school_id])
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @step = params[:step]
      @grade = params[:grade]
      @class_count = params[:class_count]
      @bulk_errors = []

      return unless @step == "assign"

      @class_rows = bulk_class_rows_from_count
    end

    def create
      @school = School.find_by(id: params.dig(:participant_group, :school_id))
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @participant_group = @school.participant_groups.build(participant_group_params.merge(purpose: :school_election))

      if @participant_group.save
        redirect_to admin_election_rosters_path(school_id: @school.id), notice: "학급을 추가했습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def bulk_create
      @school = School.find_by(id: params[:school_id])
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @step = "assign"
      @grade = params[:grade]
      @bulk_errors = []
      @class_rows = submitted_class_rows
      validate_class_rows
      validate_duplicate_classes

      if @bulk_errors.any?
        render :new_bulk, status: :unprocessable_entity
        return
      end

      ParticipantGroup.transaction do
        @class_rows.each do |row|
          @school.participant_groups.create!(
            purpose: :school_election,
            grade: @grade.to_i,
            class_label: row["class_label"],
            user_id: row["teacher_id"]
          )
        end
      end

      redirect_to admin_election_rosters_path(school_id: @school.id), notice: "학년 단위로 학급을 추가했습니다."
    rescue ActiveRecord::RecordInvalid => e
      @bulk_errors << e.record.errors.full_messages.to_sentence
      render :new_bulk, status: :unprocessable_entity
    end

    def edit
      @school = @participant_group.school
    end

    def update
      if @participant_group.update(participant_group_params)
        redirect_to admin_election_rosters_path(school_id: @participant_group.school_id), notice: "전교임원선거 학급 명단을 수정했습니다."
      else
        @school = @participant_group.school
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      school_id = @participant_group.school_id

      if ElectionSession.roster_locking.where(participant_group: @participant_group).exists?
        redirect_to admin_election_rosters_path(school_id: school_id), alert: "선거 세션에 연결된 학급 명단은 삭제할 수 없습니다."
        return
      end

      ParticipantGroup.transaction do
        ElectionSession.stopped.where(participant_group: @participant_group).destroy_all
        @participant_group.destroy!
      end

      redirect_to admin_election_rosters_path(school_id: school_id), notice: "전교임원선거 학급 명단을 삭제했습니다."
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      message = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : nil
      redirect_to admin_election_rosters_path(school_id: school_id), alert: message.presence || "전교임원선거 학급 명단을 삭제할 수 없습니다."
    end

    def edit_students
      @new_count = parsed_new_count
      prepare_student_rows
    end

    def update_students
      result = ParticipantGroups::UpdateRoster.new(
        participant_group: @participant_group,
        slot_attributes: roster_params.fetch("slots", {}),
        new_slot_attributes: roster_params.fetch("new_slots", {})
      ).call

      if result.success?
        redirect_to admin_election_rosters_path(school_id: @participant_group.school_id), notice: "학생 명단을 수정했습니다."
      else
        @roster_errors = result.errors
        @slot_rows = result.slot_rows
        @new_slot_rows = result.new_slot_rows
        @new_count = @new_slot_rows.size
        render :edit_students, status: :unprocessable_entity
      end
    end

    private

    def set_participant_group
      @participant_group = ParticipantGroup.school_election.find(params[:id])
    end

    def set_teachers
      @teachers = User.teacher.order(:name, :email)
    end

    def selected_school
      return School.find_by(id: params[:school_id]) if params[:school_id].present?

      @schools.first
    end

    def participant_group_params
      params.require(:participant_group).permit(:user_id, :grade, :class_label)
    end

    def roster_params
      params.require(:roster).permit(slots: {}, new_slots: {}).to_h
    end

    def parsed_new_count
      count = params[:new_count].to_i
      return 0 if count < 1

      [count, 40].min
    end

    def prepare_student_rows
      @roster_errors = []
      @slot_rows = @participant_group.participant_slots.order(:number).map do |slot|
        { "id" => slot.id.to_s, "number" => slot.number, "name" => slot.name, "_destroy" => "0" }
      end
      next_number = @participant_group.participant_slots.maximum(:number).to_i + 1
      @new_slot_rows = Array.new(@new_count) do |index|
        { "number" => next_number + index, "name" => "" }
      end
    end

    def bulk_class_rows_from_count
      grade = @grade.to_i
      class_count = @class_count.to_i

      @bulk_errors << "학년은 1 이상의 숫자로 입력하세요." if grade < 1
      @bulk_errors << "학급 수는 1 이상의 숫자로 입력하세요." if class_count < 1
      @bulk_errors << "한 번에 최대 30개 학급까지만 추가할 수 있습니다." if class_count > 30

      return [] if @bulk_errors.any?

      Array.new(class_count) do |index|
        { "class_label" => (index + 1).to_s, "teacher_id" => "" }
      end
    end

    def submitted_class_rows
      rows = params[:class_rows]
      return [] if rows.blank?

      row_hash = rows.respond_to?(:to_unsafe_h) ? rows.to_unsafe_h : rows
      row_hash.values.map do |row|
        {
          "class_label" => row["class_label"].to_s.strip,
          "teacher_id" => row["teacher_id"].to_s
        }
      end
    end

    def validate_class_rows
      @bulk_errors << "학년은 1 이상의 숫자로 입력하세요." if @grade.to_i < 1
      @bulk_errors << "추가할 학급을 1개 이상 남겨두세요." if @class_rows.empty?
      return if @bulk_errors.any?

      if @class_rows.any? { |row| row["class_label"].blank? }
        @bulk_errors << "모든 학급의 반을 입력하세요."
      end

      if @class_rows.any? { |row| row["teacher_id"].blank? }
        @bulk_errors << "모든 학급의 담당 교사를 선택하세요."
      end

      selected_teacher_ids = @class_rows.map { |row| row["teacher_id"].to_i }.reject(&:zero?)
      valid_teacher_ids = @teachers.where(id: selected_teacher_ids.uniq).pluck(:id)
      @bulk_errors << "담당 교사 선택이 올바르지 않습니다." if (selected_teacher_ids.uniq - valid_teacher_ids).any?
    end

    def validate_duplicate_classes
      return if @bulk_errors.any?

      duplicate_participant_groups = @school.participant_groups
                                            .school_election
                                            .where(grade: @grade.to_i)

      duplicate_labels = @class_rows.filter_map { |row| row["class_label"].presence }
      existing_duplicates = []
      existing_duplicates += duplicate_participant_groups.where(class_label: duplicate_labels).to_a if duplicate_labels.any?

      row_keys = @class_rows.map { |row| row["class_label"] }
      duplicate_row_keys = row_keys.tally.select { |_key, count| count > 1 }.keys

      return if existing_duplicates.empty? && duplicate_row_keys.empty?

      duplicate_display_names = existing_duplicates.map(&:display_name)
      duplicate_display_names += @class_rows.select { |row| duplicate_row_keys.include?(row["class_label"]) }
                                            .map { |row| class_row_display_name(row) }
                                            .uniq

      @bulk_errors << "이미 등록된 학급이 있습니다: #{duplicate_display_names.join(", ")}"
    end

    def class_row_display_name(row)
      label = row["class_label"].to_s
      label_for_display = label.match?(/\A\d+\z/) ? "#{label}반" : label
      "#{@grade.to_i}학년 #{label_for_display}"
    end
  end
end
