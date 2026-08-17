require "rails_helper"

RSpec.describe ElectionId6Recovery::DestinationVerifier do
  def verifier(school: double, poll: double, owner: double, snapshot: double)
    described_class.new(snapshot: snapshot, school: school, poll: poll, owner: owner)
  end

  def set(verifier, name, value)
    verifier.instance_variable_set("@#{name}", value)
  end

  it "rejects a destination count mismatch without exposing PII" do
    school = create(:school)
    teacher = create(:user, name: "Private Teacher", login_id: "private@example.test")
    membership = create(:school_membership, school: school, user: teacher)
    record = verifier(school: school, poll: double, owner: double, snapshot: double)
    set(record, :teachers, [teacher])
    set(record, :memberships, [membership])

    expect { record.send(:verify_school_and_teachers) }
      .to raise_error(ElectionId6Recovery::DestinationContractError) do |error|
        expect(error.message).to match(/teacher/)
        expect(error.message).not_to include("Private Teacher", "private@example.test")
      end
  end

  it "rejects inactive imported Classrooms" do
    record = verifier
    classrooms = Array.new(40) { double(active?: false) }
    set(record, :classrooms, classrooms)
    set(record, :students, [])
    set(record, :memberships, [])

    expect { record.send(:verify_classrooms_and_students) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /active classrooms/)
  end

  it "rejects a contest completion count mismatch" do
    record = verifier
    allow(PollParticipation).to receive(:count)
      .and_return(ElectionId6Recovery::EXPECTED_STUDENTS)
    allow(PollContestCompletion).to receive(:count)
      .and_return(ElectionId6Recovery::EXPECTED_CONTEST_COMPLETIONS)
    participant_class = Data.define(:id)
    participation_class = Data.define(:poll_participant_id, :status) do
      def completed? = status == :completed
      def absent? = status == :absent
      def abstained? = status == :abstained
    end
    participants = (1..967).map { |id| participant_class.new(id: id) }
    statuses = Array.new(947, :completed) + Array.new(14, :absent) + Array.new(6, :abstained)
    participations = participants.zip(statuses).map do |participant, status|
      participation_class.new(poll_participant_id: participant.id, status: status)
    end
    set(record, :participants, participants)
    set(record, :participations, participations)
    set(record, :completions, Array.new(2_858))

    expect { record.send(:verify_participation) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /contest completions/)
  end

  it "rejects a Session and Contest tally equation mismatch" do
    record = verifier
    session_class = Data.define(:id)
    contest_class = Data.define(:id, :position)
    option_class = Data.define(:poll_contest_id)
    option_tally_class = Data.define(:poll_session_id, :poll_option, :votes_count)
    contest_tally_class = Data.define(:poll_session_id, :poll_contest_id, :abstentions_count)
    participant_class = Data.define(:poll_session_id)
    participation_class = Data.define(:poll_participant) do
      def absent? = false
    end
    sessions = (1..40).map { |id| session_class.new(id: id) }
    contests = (1..3).map { |id| contest_class.new(id: id, position: id) }
    participations = sessions.flat_map do |session|
      Array.new(24) { participation_class.new(poll_participant: participant_class.new(poll_session_id: session.id)) }
    end
    option_tallies = sessions.flat_map do |session|
      contests.flat_map do |contest|
        Array.new(8) do |index|
          option_tally_class.new(
            poll_session_id: session.id,
            poll_option: option_class.new(poll_contest_id: contest.id),
            votes_count: index.zero? ? 24 : 0
          )
        end
      end
    end
    option_tallies[0] = option_tallies[0].with(votes_count: 23)
    contest_tallies = sessions.flat_map do |session|
      contests.map do |contest|
        contest_tally_class.new(
          poll_session_id: session.id,
          poll_contest_id: contest.id,
          abstentions_count: 0
        )
      end
    end
    set(record, :sessions, sessions)
    set(record, :contests, contests)
    set(record, :participations, participations)
    set(record, :option_tallies, option_tallies)
    set(record, :contest_tallies, contest_tallies)

    expect { record.send(:verify_tally_equations) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /session contest tally equations/)
  end

  it "rejects a whole-election Contest total mismatch" do
    record = verifier
    allow(record).to receive(:check).and_call_original
    allow(record).to receive(:check)
      .with("session contest tally equations", anything, 120)
    set(record, :sessions, [])
    set(record, :participations, [])
    set(record, :contests, [double(id: 1, position: 1)])
    set(record, :option_tallies, [])
    set(record, :contest_tallies, [])

    expect { record.send(:verify_tally_equations) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /contest 1 votes/)
  end

  it "rejects a missing candidate photo" do
    record = verifier
    set(record, :options, Array.new(24) { double(photo: double(attached?: false)) })

    expect { record.send(:verify_photos) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /photos attached/)
  end

  it "rejects a destination photo checksum mismatch" do
    contest = double(position: 1)
    service = double(exist?: true)
    source_candidates = (1..24).map do |number|
      { id: number, election_contest_id: 1, number: number }
    end
    source_photos = (1..24).map do |number|
      { election_candidate_id: number, byte_size: 10, checksum: "source-checksum",
        content_type: "image/jpeg", filename: "candidate.jpg" }
    end
    snapshot = double(
      candidates: source_candidates,
      contests: [{ id: 1, position: 1 }],
      photos: source_photos
    )
    record = verifier(snapshot: snapshot)
    options = (1..24).map do |number|
      checksum = number == 1 ? "changed-checksum" : "source-checksum"
      blob = double(
        byte_size: 10, checksum: checksum, content_type: "image/jpeg",
        filename: ActiveStorage::Filename.new("candidate.jpg"), service: service,
        key: "destination-key-#{number}"
      )
      double(number: number, poll_contest: contest,
             photo: double(attached?: true, blob: blob))
    end
    set(record, :options, options)

    expect { record.send(:verify_photos) }
      .to raise_error(ElectionId6Recovery::DestinationContractError, /photos verified/)
  end
end
