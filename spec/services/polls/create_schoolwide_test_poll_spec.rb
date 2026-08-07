require "rails_helper"

RSpec.describe Polls::CreateSchoolwideTestPoll do
  def create_classroom(school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    classroom
  end

  def create_source(actor: create(:user, :admin))
    school = create(:school)
    source = create(:poll, title: "전교어린이회임원선거", user: actor, school: school,
                           school_managed: true, participant_group: nil)
    contest = create(:poll_contest, poll: source, title: "회장", position: 1)
    photo_option = create(:poll_option, poll: source, poll_contest: contest,
                                        number: 1, name: "사진 후보")
    photo_option.photo.attach(io: StringIO.new("photo"), filename: "candidate.jpg",
                              content_type: "image/jpeg")
    create(:poll_option, poll: source, poll_contest: contest, number: 2, name: "사진 없음")
    classrooms = 2.times.map { create_classroom(school) }
    classrooms.each do |classroom|
      create(:poll_session, poll: source, classroom: classroom, operator: classroom.teacher)
    end
    [source, classrooms]
  end

  it "clones definition, selected Sessions, and photo into an independent draft snapshot" do
    admin = create(:user, :admin)
    source, classrooms = create_source(actor: admin)
    source_attributes = source.attributes.slice("status", "started_at", "closed_at", "stopped_at", "archived_at")
    source_session_ids = source.poll_session_ids

    result = described_class.new(source_poll: source, classroom_ids: [classrooms.first.id],
                                 actor: admin).call

    expect(result).to be_success
    test_poll = result.poll
    expect(test_poll).to have_attributes(
      title: "전교어린이회임원선거 (테스트)", kind: source.kind,
      school: source.school, user: admin, test_source_poll: source,
      school_managed: true, status: "draft", started_at: nil, closed_at: nil,
      stopped_at: nil, archived_at: nil
    )
    expect(test_poll.poll_sessions.map(&:classroom)).to contain_exactly(classrooms.first)
    expect(test_poll.poll_sessions.sole).to have_attributes(status: "draft", replacement_of_id: nil)
    expect(test_poll.poll_participants).to be_empty
    expect(test_poll.poll_progress).to be_nil
    expect(test_poll.poll_option_tallies).to be_empty
    expect(test_poll.poll_contest_tallies).to be_empty
    expect(test_poll.poll_events).to be_empty

    cloned_contest = test_poll.poll_contests.sole
    cloned_options = cloned_contest.poll_options.order(:number)
    expect(cloned_contest).not_to eq(source.poll_contests.sole)
    expect(cloned_contest).to have_attributes(title: "회장", position: 1)
    expect(cloned_options.pluck(:number, :name)).to eq([[1, "사진 후보"], [2, "사진 없음"]])
    expect(cloned_options.first).not_to eq(source.poll_options.order(:number).first)
    expect(cloned_options.first.photo).to be_attached
    expect(cloned_options.first.photo.blob.id).not_to eq(source.poll_options.order(:number).first.photo.blob.id)
    expect(cloned_options.second.photo).not_to be_attached
    source.poll_contests.sole.update!(title: "원본 수정")
    source.poll_options.order(:number).first.update!(name: "원본 후보 수정")
    source.poll_options.order(:number).first.photo.purge
    expect(cloned_contest.reload.title).to eq("회장")
    expect(cloned_options.first.reload.name).to eq("사진 후보")
    expect(cloned_options.first.photo).to be_attached
    expect(source.reload.attributes.slice(*source_attributes.keys)).to eq(source_attributes)
    expect(source.poll_session_ids).to eq(source_session_ids)
  end

  it "rejects invalid sources, empty selection, and an unassigned Classroom" do
    admin = create(:user, :admin)
    source, classrooms = create_source(actor: admin)
    unassigned = create_classroom(source.school)
    expect(described_class.new(source_poll: source, classroom_ids: [], actor: admin).call).not_to be_success
    expect(described_class.new(source_poll: source, classroom_ids: [unassigned.id], actor: admin).call).not_to be_success

    %i[in_progress closed stopped].each do |status|
      invalid, invalid_classrooms = create_source(actor: admin)
      invalid.update!(status: status, started_at: 1.hour.ago,
                      closed_at: (Time.current if status == :closed),
                      stopped_at: (Time.current if status == :stopped))
      expect(described_class.new(source_poll: invalid,
                                 classroom_ids: [invalid_classrooms.first.id], actor: admin).call).not_to be_success
    end

    source.update!(archived_at: Time.current)
    expect(described_class.new(source_poll: source, classroom_ids: [classrooms.first.id],
                               actor: admin).call).not_to be_success
  end

  it "does not leave an immutable test Poll when the cloned definition is not startable" do
    admin = create(:user, :admin)
    source, classrooms = create_source(actor: admin)
    source.poll_options.order(:number).last.destroy!

    expect do
      result = described_class.new(
        source_poll: source,
        classroom_ids: [classrooms.first.id],
        actor: admin
      ).call

      expect(result).not_to be_success
    end.not_to change { source.test_polls.count }
  end

  it "rejects cloning a test Poll and unauthorized teachers" do
    admin = create(:user, :admin)
    source, classrooms = create_source(actor: admin)
    test_poll = create(:poll, school: source.school, school_managed: true,
                              participant_group: nil, test_source_poll: source)
    test_session = create(:poll_session, poll: test_poll, classroom: classrooms.first,
                                         operator: classrooms.first.teacher)

    expect(described_class.new(source_poll: test_poll,
                               classroom_ids: [test_session.classroom_id], actor: admin).call).not_to be_success
    expect(described_class.new(source_poll: source,
                               classroom_ids: [classrooms.first.id], actor: create(:user)).call).not_to be_success
  end

  it "rolls back the clone when definition persistence fails" do
    admin = create(:user, :admin)
    source, classrooms = create_source(actor: admin)
    allow_any_instance_of(PollOption).to receive(:save!).and_raise(
      ActiveRecord::RecordInvalid.new(source.poll_options.first)
    )

    expect do
      result = described_class.new(source_poll: source,
                                   classroom_ids: [classrooms.first.id], actor: admin).call
      expect(result).not_to be_success
    end.not_to change { source.test_polls.count }
  end
end
