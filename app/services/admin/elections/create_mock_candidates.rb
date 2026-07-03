module Admin
  module Elections
    class CreateMockCandidates
      ElectionNotDraftError = Class.new(StandardError)
      CANDIDATES_PER_CONTEST = 15
      NAME_SETS = [
        %w[김하준 이서윤 박도윤 최지민 정민재 한서연 오태윤 윤다은 장유찬 임수빈 신도현 조하린 강민준 배서아 서지안],
        %w[김도현 이지안 박준서 최하윤 정유진 한민준 오서아 윤지후 장다인 임현우 신예린 조시우 강채원 배도윤 서하린],
        %w[김유찬 이수빈 박민재 최서연 정지호 한다은 오하준 윤지민 장도현 임서윤 신민준 조서아 강지후 배하윤 서유진]
      ].freeze

      def initialize(election:)
        @election = election
      end

      def call
        created_count = 0

        election.with_lock do
          raise ElectionNotDraftError unless election.draft?

          election.election_contests.order(:position).each_with_index do |contest, index|
            next if contest.election_candidates.exists?

            names_for(index).each_with_index do |name, candidate_index|
              contest.election_candidates.create!(number: candidate_index + 1, name: name)
              created_count += 1
            end
          end
        end

        created_count
      end

      private

      attr_reader :election

      def names_for(contest_index)
        NAME_SETS.fetch(contest_index % NAME_SETS.size).first(CANDIDATES_PER_CONTEST)
      end
    end
  end
end
