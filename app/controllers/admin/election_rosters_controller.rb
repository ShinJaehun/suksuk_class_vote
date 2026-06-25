module Admin
  class ElectionRostersController < BaseController
    before_action :set_participant_group, only: %i[edit update destroy]
    before_action :set_teachers, only: %i[new create edit update new_bulk bulk_create]

    def index
      @schools = School.order(:name)
      @school = selected_school
      if params[:school_id].present? && @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 찾을 수 없습니다."
        return
      end

      @participant_groups = if @school.present?
        @school.participant_groups.school_election.includes(:user, :participant_slots).order(:grade, :class_number, :name)
      else
        ParticipantGroup.none
      end
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
      @start_class_number = params[:start_class_number]
      @end_class_number = params[:end_class_number]
      @bulk_errors = []

      return unless @step == "assign"

      @class_numbers = bulk_class_numbers
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
      @start_class_number = params[:start_class_number]
      @end_class_number = params[:end_class_number]
      @bulk_errors = []
      @class_numbers = bulk_class_numbers
      validate_duplicate_classes
      validate_teacher_assignments

      if @bulk_errors.any?
        render :new_bulk, status: :unprocessable_entity
        return
      end

      ParticipantGroup.transaction do
        @class_numbers.each do |class_number|
          @school.participant_groups.create!(
            purpose: :school_election,
            grade: @grade.to_i,
            class_number: class_number,
            user_id: teacher_assignments[class_number.to_s]
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

      if @participant_group.destroy
        redirect_to admin_election_rosters_path(school_id: school_id), notice: "전교임원선거 학급 명단을 삭제했습니다."
      else
        redirect_to admin_election_rosters_path(school_id: school_id), alert: @participant_group.errors.full_messages.to_sentence
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
      params.require(:participant_group).permit(:user_id, :grade, :class_number, :name)
    end

    def bulk_class_numbers
      if params[:class_numbers_present].present?
        class_numbers = Array(params[:class_numbers]).filter_map do |class_number|
          Integer(class_number, exception: false)
        end.uniq

        @bulk_errors << "추가할 학급을 1개 이상 남겨두세요." if class_numbers.empty?
        return @bulk_errors.empty? ? class_numbers : []
      end

      grade = @grade.to_i
      start_class_number = @start_class_number.to_i
      end_class_number = @end_class_number.to_i

      @bulk_errors << "학년은 1 이상의 숫자로 입력하세요." if grade < 1
      @bulk_errors << "시작 반은 1 이상의 숫자로 입력하세요." if start_class_number < 1
      @bulk_errors << "끝 반은 1 이상의 숫자로 입력하세요." if end_class_number < 1
      @bulk_errors << "시작 반은 끝 반보다 클 수 없습니다." if start_class_number.positive? && end_class_number.positive? && start_class_number > end_class_number

      class_numbers = start_class_number..end_class_number
      @bulk_errors << "한 번에 최대 30개 반까지만 추가할 수 있습니다." if @bulk_errors.empty? && class_numbers.count > 30

      @bulk_errors.empty? ? class_numbers.to_a : []
    end

    def validate_teacher_assignments
      return if @bulk_errors.any?

      missing_class_numbers = @class_numbers.select { |class_number| teacher_assignments[class_number.to_s].blank? }
      if missing_class_numbers.any?
        @bulk_errors << "모든 학급의 담당 교사를 선택하세요."
        return
      end

      selected_teacher_ids = teacher_assignments.values_at(*@class_numbers.map(&:to_s)).map(&:to_i)
      valid_teacher_ids = @teachers.where(id: selected_teacher_ids.uniq).pluck(:id)
      @bulk_errors << "담당 교사 선택이 올바르지 않습니다." if (selected_teacher_ids.uniq - valid_teacher_ids).any?
    end

    def validate_duplicate_classes
      return if @bulk_errors.any?

      duplicate_participant_groups = @school.participant_groups
                                            .school_election
                                            .where(grade: @grade.to_i, class_number: @class_numbers)
                                            .order(:grade, :class_number, :name)
      return if duplicate_participant_groups.empty?

      @bulk_errors << "이미 등록된 학급이 있습니다: #{duplicate_participant_groups.map { |participant_group| "#{participant_group.grade}학년 #{participant_group.class_number}반" }.join(", ")}"
    end

    def teacher_assignments
      assignments = params[:teacher_assignments]
      return {} if assignments.blank?

      assignments.respond_to?(:to_unsafe_h) ? assignments.to_unsafe_h : assignments
    end

  end
end
