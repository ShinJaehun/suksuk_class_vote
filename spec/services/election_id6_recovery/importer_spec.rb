require "rails_helper"
require "tmpdir"

RSpec.describe ElectionId6Recovery::Importer do
  def build_snapshot(storage_root)
    contests = (1..3).map { |position| { id: position, title: "Contest", position: position } }
    candidates = contests.flat_map do |contest|
      (1..8).map do |number|
        { id: ((contest[:id] - 1) * 8) + number,
          election_contest_id: contest[:id], number: number, name: "Candidate" }
      end
    end
    sessions = (1..40).map do |id|
      { id: id, teacher_id: id, participant_group_id: id, status: 20,
        started_at: "2026-07-16 01:00:00", closed_at: "2026-07-16 02:00:00" }
    end
    teachers = (1..40).map do |id|
      { id: id, email: "teacher#{id}@example.test", name: "Teacher #{id}", role: 0 }
    end
    groups = (1..40).map do |id|
      { id: id, user_id: id, school_id: 1, grade: ((id - 1) % 6) + 1,
        class_label: id.to_s, name: "Class #{id}" }
    end
    slots = []
    voters = []
    967.times do |index|
      group_id = (index % 40) + 1
      number = (index / 40) + 1
      id = index + 1
      slots << { id: id, participant_group_id: group_id, number: number, name: "Student" }
      voters << { id: id, election_session_id: group_id,
                  source_participant_slot_id: id, number: number, name: "Student" }
    end
    participations = voters.each_with_index.map do |voter, index|
      status = index < 947 ? 10 : (index < 961 ? 20 : 30)
      { election_voter_id: voter[:id], status: status, submitted_at: "2026-07-16 01:30:00" }
    end
    participated = Hash.new(0)
    participations.each do |participation|
      next if participation[:status] == 20

      participated[voters.fetch(participation[:election_voter_id] - 1)[:election_session_id]] += 1
    end
    abstention_totals = { 1 => 9, 2 => 25, 3 => 23 }
    candidate_tallies = []
    contest_tallies = []
    sessions.each do |session|
      contests.each do |contest|
        abstentions = session[:id] <= abstention_totals.fetch(contest[:position]) ? 1 : 0
        contest_tallies << { election_session_id: session[:id],
                             election_contest_id: contest[:id],
                             abstentions_count: abstentions }
        candidates.select { |candidate| candidate[:election_contest_id] == contest[:id] }
          .each_with_index do |candidate, index|
          candidate_tallies << {
            election_session_id: session[:id],
            election_contest_id: contest[:id],
            election_candidate_id: candidate[:id],
            votes_count: index.zero? ? participated[session[:id]] - abstentions : 0
          }
        end
      end
    end
    photos = candidates.map do |candidate|
      content = "photo-#{candidate[:id]}"
      key = format("%04d-safe-key", candidate[:id])
      path = File.join(storage_root, key[0, 2], key[2, 2], key)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      { election_candidate_id: candidate[:id], key: key,
        filename: "candidate.jpg", content_type: "image/jpeg",
        checksum: Base64.strict_encode64(Digest::MD5.digest(content)),
        byte_size: content.bytesize }
    end

    ElectionId6Recovery::Snapshot.new(
      election: { id: 6, school_id: 1, title: "Historical Election",
                  started_at: "2026-07-16 01:00:00", closed_at: "2026-07-16 02:00:00" },
      school: { id: 1, name: "아라초등학교" }, teachers: teachers,
      groups: groups, slots: slots, contests: contests, candidates: candidates,
      sessions: sessions,
      stopped_sessions: [{ status: 30, participant_group_id: 1 },
                         { status: 30, participant_group_id: 2 }],
      session_status_counts: [{ status: 20, count: 40 }, { status: 30, count: 2 }],
      voters: voters, participations: participations,
      progresses: sessions.map do |session|
        { election_session_id: session[:id], started_at: session[:started_at],
          closed_at: session[:closed_at] }
      end,
      candidate_tallies: candidate_tallies, contest_tallies: contest_tallies,
      photos: photos, storage_root: storage_root
    )
  end

  def create_owner(active: true, role: :admin)
    create(:user, role: role, active: active, login_id: "recovery-owner")
  end

  it "imports the verified graph and publishes credentials after commit" do
    Dir.mktmpdir do |directory|
      owner = create_owner
      snapshot = build_snapshot(File.join(directory, "source"))
      credentials_path = File.join(directory, "credentials.csv")
      expect(PollSession).to receive(:with_schoolwide_runtime_broadcast_suppressed).and_call_original

      result = described_class.new(
        snapshot: snapshot,
        owner_login_id: owner.login_id,
        credentials_path: credentials_path
      ).call

      expect(result.summary).to include(teachers: 40, students: 967, photos: 24)
      expect(Classroom.where(active: true).count).to eq(40)
      expect(User.teacher.where(password_change_required: true).count).to eq(40)
      expect(PollSession.count).to eq(40)
      expect(PollParticipation.group(:status).count).to eq(
        "completed" => 947, "absent" => 14, "abstained" => 6
      )
      expect(PollContestCompletion.count).to eq(2_859)
      expect(File.stat(credentials_path).mode & 0o777).to eq(0o600)
      expect(CSV.read(credentials_path, headers: true).headers)
        .to eq(%w[login_id temporary_password])

      session = PollSession.order(:id).first
      tallies = session.poll_option_tallies
        .joins(:poll_option)
        .where(poll_options: { poll_contest_id: PollContest.order(:position).first.id })
        .order("poll_options.number")
        .first(2)
      tallies.first.update!(votes_count: tallies.first.votes_count - 1)
      tallies.second.update!(votes_count: tallies.second.votes_count + 1)

      expect do
        ElectionId6Recovery::DestinationVerifier.new(
          snapshot: snapshot, school: result.school, poll: result.poll, owner: owner
        ).verify
      end.to raise_error(ElectionId6Recovery::DestinationContractError,
                         /source option tally parity/)
    end
  end

  it "writes nothing when source verification fails" do
    allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
      .and_raise(ElectionId6Recovery::SourceContractError, "source count mismatch")

    expect do
      described_class.new(snapshot: nil, owner_login_id: "owner", credentials_path: "/tmp/unused").call
    end.to raise_error(ElectionId6Recovery::SourceContractError)
    expect(School.count).to eq(0)
  end

  it "fails closed for a dirty destination" do
    Dir.mktmpdir do |directory|
      owner = create_owner
      School.create!(name: "Existing School")
      allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
        .and_return(instance_double(ElectionId6Recovery::SourceVerifier, verify: {}))

      expect do
        described_class.new(
          snapshot: double(teachers: []), owner_login_id: owner.login_id,
          credentials_path: File.join(directory, "credentials.csv")
        ).call
      end.to raise_error(ElectionId6Recovery::ImportError, /destination schools/)
    end
  end

  it "rejects an inactive or non-admin owner" do
    Dir.mktmpdir do |directory|
      owner = create_owner(active: false)
      allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
        .and_return(instance_double(ElectionId6Recovery::SourceVerifier, verify: {}))

      expect do
        described_class.new(
          snapshot: double, owner_login_id: owner.login_id,
          credentials_path: File.join(directory, "credentials.csv")
        ).call
      end.to raise_error(ElectionId6Recovery::ImportError, /owner active/)
    end
  end

  it "rejects a non-admin owner" do
    Dir.mktmpdir do |directory|
      owner = create_owner(role: :teacher)
      allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
        .and_return(instance_double(ElectionId6Recovery::SourceVerifier, verify: {}))

      expect do
        described_class.new(
          snapshot: double, owner_login_id: owner.login_id,
          credentials_path: File.join(directory, "credentials.csv")
        ).call
      end.to raise_error(ElectionId6Recovery::ImportError, /owner role/)
    end
  end

  it "rejects an existing final credentials path before import" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.csv")
      File.write(path, "existing")
      allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
        .and_return(instance_double(ElectionId6Recovery::SourceVerifier, verify: {}))

      expect do
        described_class.new(snapshot: double, owner_login_id: "owner", credentials_path: path).call
      end.to raise_error(ElectionId6Recovery::ImportError, /credentials path/)
      expect(File.read(path)).to eq("existing")
    end
  end

  it "does not overwrite a credentials file created after preflight" do
    Dir.mktmpdir do |directory|
      owner = create_owner
      path = File.join(directory, "credentials.csv")
      snapshot = double(teachers: [])
      allow(ElectionId6Recovery::SourceVerifier).to receive(:new)
        .and_return(instance_double(ElectionId6Recovery::SourceVerifier, verify: {}))
      verifier = instance_double(ElectionId6Recovery::DestinationVerifier, verify: {})
      allow(ElectionId6Recovery::DestinationVerifier).to receive(:new).and_return(verifier)
      importer = described_class.new(
        snapshot: snapshot, owner_login_id: owner.login_id, credentials_path: path
      )
      allow(importer).to receive(:import_records!) do
        File.write(path, "existing")
        [double, double]
      end

      expect { importer.call }
        .to raise_error(ElectionId6Recovery::ImportError, /destination exists/)
      expect(File.read(path)).to eq("existing")
    end
  end

  it "rolls back destination rows and does not publish credentials on verifier failure" do
    Dir.mktmpdir do |directory|
      owner = create_owner
      snapshot = build_snapshot(File.join(directory, "source"))
      credentials_path = File.join(directory, "credentials.csv")
      service = ActiveStorage::Blob.service
      uploaded_keys = []
      allow(service).to receive(:upload).and_wrap_original do |method, *args, **kwargs|
        uploaded_keys << args.first
        method.call(*args, **kwargs)
      end
      allow(service).to receive(:delete).and_call_original
      verifier = instance_double(ElectionId6Recovery::DestinationVerifier)
      allow(verifier).to receive(:verify)
        .and_raise(ElectionId6Recovery::DestinationContractError, "count mismatch")
      allow(ElectionId6Recovery::DestinationVerifier).to receive(:new).and_return(verifier)

      expect do
        described_class.new(
          snapshot: snapshot, owner_login_id: owner.login_id,
          credentials_path: credentials_path
        ).call
      end.to raise_error(ElectionId6Recovery::DestinationContractError)
      expect(School.count).to eq(0)
      expect(Poll.count).to eq(0)
      expect(ActiveStorage::Blob.count).to eq(0)
      expect(ActiveStorage::Attachment.count).to eq(0)
      expect(File).not_to exist(credentials_path)
      expect(uploaded_keys.size).to eq(24)
      expect(service).to have_received(:delete).exactly(24).times
      uploaded_keys.each do |key|
        expect(service).to have_received(:delete).with(key)
      end
    end
  end

  it "preserves storage and temporary credentials when an exception follows a committed transaction" do
    Dir.mktmpdir do |directory|
      owner = create_owner
      snapshot = build_snapshot(File.join(directory, "source"))
      credentials_path = File.join(directory, "credentials.csv")
      service = ActiveStorage::Blob.service
      allow(service).to receive(:delete).and_call_original
      allow(ApplicationRecord).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
        method.call(*args, **kwargs, &block)
        raise RuntimeError, "simulated post-commit failure"
      end

      error = nil
      expect do
        described_class.new(
          snapshot: snapshot, owner_login_id: owner.login_id,
          credentials_path: credentials_path
        ).call
      end.to raise_error(ElectionId6Recovery::ImportError) { |raised| error = raised }

      expect(error.message).to include("database committed")
      expect(error.message).not_to include("simulated post-commit failure")
      temporary_path = error.message[/preserved at (.+)\z/, 1]
      expect(Poll.count).to eq(1)
      expect(service).not_to have_received(:delete)
      expect(File).not_to exist(credentials_path)
      expect(File).to exist(temporary_path)
    end
  end
end
