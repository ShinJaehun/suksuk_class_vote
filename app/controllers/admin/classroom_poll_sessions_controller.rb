module Admin
  class ClassroomPollSessionsController < BaseController
    def index
      authorize PollSession, :index?, policy_class: Admin::ClassroomPollSessionPolicy
      query = Admin::ClassroomPollSessionsQuery.new(scope: base_scope, params: params)
      @schools = School.order(:name, :id)
      @school = query.school
      @grade = query.grade
      @classroom = query.classroom
      @status = query.status
      @classroom_options = query.classroom_options
      @poll_sessions = query.call.preload(
        :poll,
        :operator,
        :replacement_of,
        :replacement_session,
        classroom: :school
      )
      @participation_counts = participation_counts_for(@poll_sessions.map(&:id))
    end

    def show
      @poll_session = find_poll_session
      authorize @poll_session, :show?, policy_class: Admin::ClassroomPollSessionPolicy
      @participation_counts = participation_counts_for([@poll_session.id]).fetch(@poll_session.id, empty_counts)
    end

    def results
      @poll_session = find_poll_session
      authorize @poll_session, :results?, policy_class: Admin::ClassroomPollSessionPolicy
      raise ActiveRecord::RecordNotFound unless @poll_session.closed?

      @participation_counts = participation_counts_for([@poll_session.id]).fetch(@poll_session.id, empty_counts)
      prepare_results
    end

    private

    def base_scope
      PollSession.joins(:poll, classroom: :school).where(polls: { school_managed: false })
    end

    def find_poll_session
      Admin::ClassroomPollSessionsQuery
        .with_representative_activity(base_scope)
        .preload(
          :operator,
          :replacement_of,
          :replacement_session,
          {
            classroom: :school,
            poll: { poll_contests: :poll_options },
            poll_option_tallies: :poll_option,
            poll_contest_tallies: :poll_contest
          }
        )
        .find(params[:id])
    end

    def participation_counts_for(poll_session_ids)
      return {} if poll_session_ids.empty?

      rows = PollParticipant
        .left_joins(:poll_participation)
        .where(poll_session_id: poll_session_ids)
        .group(:poll_session_id)
        .pluck(
          :poll_session_id,
          Arel.sql("COUNT(poll_participants.id)"),
          Arel.sql("COUNT(CASE WHEN poll_participations.status = #{PollParticipation.statuses.fetch('completed')} THEN 1 END)"),
          Arel.sql("COUNT(CASE WHEN poll_participations.status = #{PollParticipation.statuses.fetch('absent')} THEN 1 END)"),
          Arel.sql("COUNT(CASE WHEN poll_participations.status = #{PollParticipation.statuses.fetch('abstained')} THEN 1 END)"),
          Arel.sql("COUNT(CASE WHEN poll_participations.id IS NULL THEN 1 END)")
        )

      rows.to_h do |session_id, total, completed, absent, abstained, pending|
        [session_id, { total: total, completed: completed, absent: absent, abstained: abstained, pending: pending }]
      end
    end

    def empty_counts
      { total: 0, completed: 0, absent: 0, abstained: 0, pending: 0 }
    end

    def prepare_results
      option_tallies = @poll_session.poll_option_tallies.index_by(&:poll_option_id)
      contest_tallies = @poll_session.poll_contest_tallies.index_by(&:poll_contest_id)
      @contest_results = @poll_session.poll.poll_contests.sort_by { |contest| [contest.position, contest.id] }.map do |contest|
        {
          contest: contest,
          options: contest.poll_options.sort_by { |option| [option.number, option.id] }.map do |option|
            { option: option, votes_count: option_tallies[option.id]&.votes_count }
          end,
          tally: contest_tallies[contest.id]
        }
      end
    end
  end
end
