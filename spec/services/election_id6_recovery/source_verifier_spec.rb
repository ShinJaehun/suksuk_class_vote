require "rails_helper"
require "tmpdir"

RSpec.describe ElectionId6Recovery::SourceVerifier do
  def with_snapshot
    Dir.mktmpdir do |storage_root|
      yield build_snapshot(storage_root)
    end
  end

  def build_snapshot(storage_root)
    contests = (1..3).map { |position| row(id: position, title: "Contest", position: position) }
    candidates = contests.flat_map do |contest|
      (1..8).map do |number|
        row(id: ((contest[:id] - 1) * 8) + number, election_contest_id: contest[:id], number: number, name: "Candidate")
      end
    end
    sessions = (1..40).map do |id|
      row(id: id, teacher_id: id, participant_group_id: id, status: 20, started_at: "2026-07-16 01:00:00.123456", closed_at: "2026-07-16T02:00:00Z")
    end
    teachers = (1..40).map { |id| row(id: id, email: "teacher#{id}@example.test", role: 0) }
    groups = (1..40).map { |id| row(id: id, user_id: id, school_id: 1, grade: 1, class_label: id.to_s, name: "Class") }

    slots = []
    voters = []
    967.times do |index|
      session_id = (index % 40) + 1
      number = (index / 40) + 1
      id = index + 1
      slots << row(id: id, participant_group_id: session_id, number: number, name: "Student")
      voters << row(id: id, election_session_id: session_id, source_participant_slot_id: id, number: number, name: "Student")
    end

    participations = voters.each_with_index.map do |voter, index|
      status = index < 947 ? 10 : (index < 961 ? 20 : 30)
      row(election_voter_id: voter[:id], status: status, submitted_at: "2026-07-16T01:30:00Z")
    end
    participated_by_session = Hash.new(0)
    participations.each do |participation|
      next if participation[:status] == 20

      participated_by_session[voters.fetch(participation[:election_voter_id] - 1)[:election_session_id]] += 1
    end

    abstentions_by_position = { 1 => 9, 2 => 25, 3 => 23 }
    candidate_tallies = []
    contest_tallies = []
    sessions.each do |session|
      contests.each do |contest|
        abstentions = session[:id] <= abstentions_by_position.fetch(contest[:position]) ? 1 : 0
        contest_tallies << row(
          election_session_id: session[:id],
          election_contest_id: contest[:id],
          abstentions_count: abstentions
        )
        contest_candidates = candidates.select { |candidate| candidate[:election_contest_id] == contest[:id] }
        contest_candidates.each_with_index do |candidate, index|
          candidate_tallies << row(
            election_session_id: session[:id],
            election_contest_id: contest[:id],
            election_candidate_id: candidate[:id],
            votes_count: index.zero? ? participated_by_session[session[:id]] - abstentions : 0
          )
        end
      end
    end

    photos = candidates.map do |candidate|
      content = "photo-#{candidate[:id]}"
      key = format("%04d-safe-key", candidate[:id])
      path = File.join(storage_root, key[0, 2], key[2, 2], key)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      row(
        election_candidate_id: candidate[:id],
        key: key,
        filename: "candidate.jpg",
        content_type: "image/jpeg",
        checksum: Base64.strict_encode64(Digest::MD5.digest(content)),
        byte_size: content.bytesize
      )
    end

    ElectionId6Recovery::Snapshot.new(
      election: row(id: 6, school_id: 1),
      school: row(id: 1, name: "아라초등학교"),
      teachers: teachers,
      groups: groups,
      slots: slots,
      contests: contests,
      candidates: candidates,
      sessions: sessions,
      stopped_sessions: [row(status: 30, participant_group_id: 1), row(status: 30, participant_group_id: 2)],
      session_status_counts: [row(status: 20, count: 40), row(status: 30, count: 2)],
      voters: voters,
      participations: participations,
      progresses: sessions.map { |session| row(election_session_id: session[:id], started_at: session[:started_at], closed_at: session[:closed_at]) },
      candidate_tallies: candidate_tallies,
      contest_tallies: contest_tallies,
      photos: photos,
      storage_root: storage_root
    )
  end

  def row(attributes)
    attributes.freeze
  end

  it "accepts a snapshot matching the recovery contract" do
    with_snapshot do |snapshot|
      summary = described_class.new(snapshot).verify

      expect(summary).to include(
        closed_sessions: 40,
        students: 967,
        contest_completions_expected: 2_859,
        photos: 24
      )
    end
  end

  it "rejects a session count mismatch without exposing PII" do
    with_snapshot do |snapshot|
      invalid = snapshot.with(sessions: snapshot.sessions.drop(1))

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, "closed sessions: expected 40, actual 39")
    end
  end

  it "rejects an unexpected session status" do
    with_snapshot do |snapshot|
      counts = [row(status: 10, count: 1), row(status: 20, count: 40), row(status: 30, count: 2)]
      invalid = snapshot.with(session_status_counts: counts)

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /all session statuses/)
    end
  end

  it "rejects a stopped session outside the final groups" do
    with_snapshot do |snapshot|
      stopped = [row(status: 30, participant_group_id: 1), row(status: 30, participant_group_id: 99)]
      invalid = snapshot.with(stopped_sessions: stopped)

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /stopped session groups are final groups/)
    end
  end

  it "rejects a participation count mismatch" do
    with_snapshot do |snapshot|
      invalid = snapshot.with(participations: snapshot.participations.drop(1))

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /participations/)
    end
  end

  it "rejects a session and contest tally equation mismatch" do
    with_snapshot do |snapshot|
      tally = snapshot.candidate_tallies.first.merge(votes_count: snapshot.candidate_tallies.first[:votes_count] + 1)
      invalid = snapshot.with(candidate_tallies: [tally, *snapshot.candidate_tallies.drop(1)])

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /session contest tally equation/)
    end
  end

  it "rejects a negative candidate tally" do
    with_snapshot do |snapshot|
      tally = snapshot.candidate_tallies.first.merge(votes_count: -1)
      invalid = snapshot.with(candidate_tallies: [tally, *snapshot.candidate_tallies.drop(1)])

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /candidate tally values/)
    end
  end

  it "rejects a negative contest tally" do
    with_snapshot do |snapshot|
      tally = snapshot.contest_tallies.first.merge(abstentions_count: -1)
      invalid = snapshot.with(contest_tallies: [tally, *snapshot.contest_tallies.drop(1)])

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /contest tally values/)
    end
  end

  it "rejects a missing photo" do
    with_snapshot do |snapshot|
      photo = snapshot.photos.first
      key = photo[:key]
      File.delete(File.join(snapshot.storage_root, key[0, 2], key[2, 2], key))

      expect { described_class.new(snapshot).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /photo file exists/)
    end
  end

  it "rejects a photo byte-size mismatch" do
    with_snapshot do |snapshot|
      photo = snapshot.photos.first.merge(byte_size: snapshot.photos.first[:byte_size] + 1)
      invalid = snapshot.with(photos: [photo, *snapshot.photos.drop(1)])

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /photo byte size/)
    end
  end

  it "rejects a photo checksum mismatch" do
    with_snapshot do |snapshot|
      photo = snapshot.photos.first.merge(checksum: "invalid")
      invalid = snapshot.with(photos: [photo, *snapshot.photos.drop(1)])

      expect { described_class.new(invalid).verify }
        .to raise_error(ElectionId6Recovery::SourceContractError, /photo checksum/)
    end
  end
end
