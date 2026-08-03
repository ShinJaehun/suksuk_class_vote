module Admin
  class ElectionSessionsController < BaseController
    before_action :set_election
    before_action :set_election_session, only: %i[destroy revote]

    def create
      authorize @election, :manage_sessions?
      unless @election.draft?
        redirect_to admin_election_path(@election), alert: "선거 시작 후에는 학급 세션을 배정할 수 없습니다."
        return
      end

      classroom = assignable_classrooms.find_by(id: election_session_params[:classroom_id])
      @election_session = @election.election_sessions.build(
        classroom: classroom,
        teacher: classroom&.teacher,
        operation_mode: :supervised
      )
      @election_session.errors.add(:classroom, "is not available for assignment") if classroom.blank?

      if @election_session.save
        redirect_to admin_election_path(@election), notice: "학급 세션을 배정했습니다."
      else
        prepare_show
        render "admin/elections/show", status: :unprocessable_content
      end
    end

    def bulk_create
      authorize @election, :manage_sessions?
      unless @election.draft?
        redirect_to admin_election_path(@election), alert: "선거 시작 후에는 학급 세션을 배정할 수 없습니다."
        return
      end

      classroom_ids = Array(params[:classroom_ids]).reject(&:blank?).uniq
      if classroom_ids.blank?
        respond_to_assignment_failure("배정할 학급을 선택하세요.")
        return
      end

      created_count = 0
      assignable_classrooms.where(id: classroom_ids).find_each do |classroom|
        election_session = @election.election_sessions.build(
          classroom: classroom,
          teacher: classroom.teacher,
          operation_mode: :supervised,
          status: :draft
        )
        created_count += 1 if election_session.save
      end

      if created_count.positive?
        respond_to_assignment_success("#{created_count}개 학급 세션을 배정했습니다.")
      else
        respond_to_assignment_failure("배정할 수 있는 학급이 없습니다.")
      end
    end

    def destroy
      authorize @election, :manage_sessions?
      unless destroyable_session?
        respond_to_assignment_failure("삭제할 수 없는 학급 세션입니다.")
        return
      end

      @election_session.destroy!
      @election_session = nil

      respond_to_assignment_success("학급 세션 배정을 해제했습니다.")
    rescue ActiveRecord::RecordNotDestroyed => e
      respond_to_assignment_failure(e.record.errors.full_messages.to_sentence.presence || "학급 세션을 등록 해제할 수 없습니다.")
    end

    def destroy_grade
      authorize @election, :manage_sessions?
      unless destroyable_sessions?
        respond_to_assignment_failure("삭제할 수 없는 학급 세션입니다.")
        return
      end

      grade = Integer(params[:grade], exception: false)
      if grade.blank? || grade <= 0
        respond_to_assignment_failure("유효한 학년을 선택하세요.")
        return
      end

      sessions = @election.election_sessions
        .includes(:classroom, :participant_group)
        .select { |session| (session.classroom || session.participant_group)&.grade == grade }

      deleted_count = 0
      ElectionSession.transaction do
        sessions.each do |session|
          session.destroy!
          deleted_count += 1
        end
      end

      respond_to_assignment_success("#{grade}학년 학급 세션 #{deleted_count}개를 등록 해제했습니다.")
    rescue ActiveRecord::RecordNotDestroyed => e
      respond_to_assignment_failure(e.record.errors.full_messages.to_sentence.presence || "학년 학급 세션을 등록 해제할 수 없습니다.")
    end

    def revote
      authorize @election_session, :revote?

      result = ::Elections::RevoteSession.new(
        election_session: @election_session,
        actor: current_user
      ).call

      if result.success?
        redirect_to elections_session_path(result.election_session), notice: "투표를 다시 시작합니다."
      else
        redirect_to elections_session_path(@election_session), alert: result.error_message
      end
    end

    private

    def set_election
      @election = policy_scope(Election).find(params[:election_id])
    end

    def set_election_session
      @election_session = @election.election_sessions.find(params[:id])
    end

    def prepare_show
      @election_contests = @election.election_contests.includes(:election_candidates).order(:position)
      @election_sessions = @election.election_sessions
        .includes(:teacher, :election_voters, participant_group: :participant_slots, classroom: :students)
        .order(:created_at)
      @election_session ||= @election.election_sessions.build(operation_mode: :supervised)
      @participant_groups = assignable_classrooms.includes(:teacher, :students)
      @election_status_report = ::Elections::StatusReport.new(election: @election).to_h
    end

    def respond_to_assignment_success(message)
      respond_to do |format|
        format.html { redirect_to admin_election_path(@election), notice: message }
        format.turbo_stream do
          flash.now[:notice] = message
          render_election_overview_streams
        end
      end
    end

    def respond_to_assignment_failure(message)
      respond_to do |format|
        format.html { redirect_to admin_election_path(@election), alert: message }
        format.turbo_stream do
          flash.now[:alert] = message
          render_election_overview_streams(status: :unprocessable_content)
        end
      end
    end

    def render_election_overview_streams(status: :ok)
      prepare_show
      render turbo_stream: [
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@election, :admin_summary),
          partial: "admin/elections/summary",
          locals: { election: @election }
        ),
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@election, :admin_status_report),
          partial: "admin/elections/status_report",
          locals: { election: @election, election_status_report: @election_status_report }
        ),
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@election, :admin_sessions),
          partial: "admin/elections/sessions",
          locals: {
            election: @election,
            election_sessions: @election_sessions,
            election_session: @election_session,
            participant_groups: @participant_groups
          }
        )
      ], status: status
    end

    def assignable_classrooms
      assigned_classroom_ids = @election.election_sessions
        .where(status: %i[draft in_progress])
        .where.not(classroom_id: nil)
        .select(:classroom_id)
      Classroom
        .where(school: @election.school, active: true)
        .where.not(teacher_id: nil)
        .joins(:students)
        .where(students: { active: true })
        .where.not(id: assigned_classroom_ids)
        .distinct
        .order(:school_year, :grade, :class_number)
    end

    def destroyable_sessions?
      @election.draft? && @election.election_sessions.where.not(status: :draft).none?
    end

    def destroyable_session?
      destroyable_sessions? && @election_session.draft?
    end

    def election_session_params
      params.require(:election_session).permit(:classroom_id)
    end
  end
end
