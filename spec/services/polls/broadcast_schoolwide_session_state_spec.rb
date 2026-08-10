require "rails_helper"

RSpec.describe Polls::BroadcastSchoolwideSessionState do
  include ActionCable::TestHelper
  include Rails.application.routes.url_helpers

  def turbo_stream_fragment(payload)
    Nokogiri::HTML.fragment(ActiveSupport::JSON.decode(payload))
  end

  it "keeps Session lifecycle broadcasts scoped to the related School Poll" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [poll, :schoolwide_runtime])
    poll.update!(status: :in_progress, started_at: Time.current)
    status_check = instance_double(
      Polls::SchoolwideStatusCheck,
      startable?: false,
      start_issues: [],
      closable?: true,
      close_issues: []
    )
    allow(Polls::SchoolwideStatusCheck).to receive(:new).and_return(status_check)

    status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
    session_target = "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime"
    status_text = lambda do
      payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(status_target) }
      turbo_stream_fragment(payload).text.squish
    end

    described_class.for_poll(poll: poll)
    expect(status_text.call).to include("전체 학급 1", "준비 1", "진행 중 0", "종료 0", "재투표 이력 0")
    expect(status_text.call).not_to include("중단 0")
    described_class.for_classroom(classroom: classroom)
    draft_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(session_target) }
    expect(draft_payload).to include("준비")
    expect(draft_payload).not_to include("학급 재투표")

    expect { session.update!(status: :in_progress, started_at: Time.current) }
      .to change { broadcasts(stream).size }.by(2)
    expect(status_text.call).to include("준비 0", "진행 중 1", "종료 0")
    running_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(session_target) }
    expect(running_payload).to include("진행 중", "학급 재투표", revote_school_poll_poll_session_path(poll, session))

    expect { session.update!(status: :closed, closed_at: Time.current) }
      .to change { broadcasts(stream).size }.by(2)
    expect(status_text.call).to include("준비 0", "진행 중 0", "종료 1")
    closed_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(session_target) }
    expect(closed_payload).to include("종료", "학급 재투표", revote_school_poll_poll_session_path(poll, session))

    stop_teacher = create(:user)
    create(:school_membership, school: school, user: stop_teacher)
    stop_classroom = create(:classroom, school: school, teacher: stop_teacher)
    stop_session = create(
      :poll_session,
      poll: poll,
      classroom: stop_classroom,
      operator: stop_teacher
    )
    stop_session.update!(status: :in_progress, started_at: Time.current)
    expect { stop_session.update!(status: :stopped, stopped_at: Time.current) }
      .to change { broadcasts(stream).size }.by(2)

    other_teacher = create(:user)
    create(:school_membership, school: school, user: other_teacher)
    other_classroom = create(:classroom, school: school, teacher: other_teacher)
    expect { described_class.for_classroom(classroom: other_classroom) }
      .not_to change { broadcasts(stream).size }

    payload = broadcasts(stream).join
    expect(payload).to include(
      session_target,
      status_target
    )
    expect(payload).not_to include(ActionView::RecordIdentifier.dom_id(poll, :revote_history))
    expect(payload).to include("모든 학급 투표가 종료되었습니다.", "전교투표 종료")
    expect(payload).not_to include("전교투표 중단")
    expect(Polls::SchoolwideStatusCheck).to have_received(:new).with(poll: poll).at_least(:twice)
  end

  it "replaces the stable classroom row with the replacement Session" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    source = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher,
      status: :closed,
      started_at: 1.hour.ago,
      closed_at: 10.minutes.ago
    )
    create(:poll_participant, poll: poll, poll_session: source, number: 1, name: "학생")
    stream = Turbo::StreamsChannel.send(:stream_name_from, [poll, :schoolwide_runtime])

    replacement = Polls::RevoteSchoolSession.new(poll_session: source, actor: manager).call.poll_session
    described_class.for_revote(poll: poll, classroom: classroom)

    session_target = "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime"
    session_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(session_target) }
    session_fragment = turbo_stream_fragment(session_payload)
    expect(session_fragment.text.squish).to include("재투표", "준비")
    expect(session_fragment.text.squish).not_to include("종료")
    expect(session_fragment.text.squish).not_to include("학급 재투표")
    session_links = session_fragment.css("a").map { |link| link["href"] }
    expect(session_links).to include(poll_poll_session_path(poll, replacement, from: "school_poll"))
    expect(session_links).not_to include(poll_poll_session_path(poll, source, from: "school_poll"))

    status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
    status_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(status_target) }
    expect(turbo_stream_fragment(status_payload).text.squish).to include(
      "전체 학급 1", "준비 1", "진행 중 0", "종료 0", "재투표 이력 1"
    )

    history_target = ActionView::RecordIdentifier.dom_id(poll, :revote_history)
    history_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(history_target) }
    history_fragment = turbo_stream_fragment(history_payload)
    expect(history_fragment.text.squish).to include("재투표 이력", "종료")
    history_links = history_fragment.css("a").map { |link| link["href"] }
    expect(history_links).to include(poll_poll_session_path(poll, source, from: "school_poll"))
    expect(history_links).not_to include(poll_poll_session_path(poll, replacement, from: "school_poll"))
  end

  it "broadcasts Test Poll start actions without the source-only test creation action" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    source = create(:poll, school: school, school_managed: true, participant_group: nil)
    test_poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                              test_source_poll: source)
    contest = create(:poll_contest, poll: test_poll)
    create(:poll_option, poll: test_poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: test_poll, poll_contest: contest, number: 2)
    create(:poll_session, poll: test_poll, classroom: classroom, operator: teacher)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [test_poll, :schoolwide_runtime])

    expect do
      described_class.for_classroom(classroom: classroom)
    end.to change { broadcasts(stream).size }.by(2)

    target = ActionView::RecordIdentifier.dom_id(test_poll, :schoolwide_status_runtime)
    payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(target) }
    expect(payload).to include("테스트투표를 시작할 수 있습니다.", "테스트투표 시작")
    expect(payload).not_to include("테스트투표 만들기")
  end

  it "continues the status broadcast after a classroom runtime failure" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, participant_group: nil)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    poll.update!(school_managed: true)
    session_target = "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime"
    status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
    attempted_targets = []
    errors = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*_streamables, **options|
      attempted_targets << options[:target]
      raise StandardError, "학생정보" if options[:target] == session_target
    end
    allow(Rails.logger).to receive(:error) { |message| errors << message }

    described_class.new(poll: poll, classroom: classroom).call

    expect(attempted_targets).to eq([session_target, status_target])
    expect(errors.join).to include(
      "poll_id=#{poll.id}", "poll_session_id=#{session.id}",
      'broadcast="classroom_runtime"', 'error_class="StandardError"'
    )
    expect(errors.join).not_to include("학생정보")
  end

  it "does not surface a schoolwide after-commit broadcast failure" do
    poll_session = create(:poll_session)
    poll_session.poll.update!(school_managed: true, status: :in_progress, started_at: Time.current)
    errors = []
    allow_any_instance_of(described_class).to receive(:call)
      .and_raise(StandardError, "학생정보")
    allow(Rails.logger).to receive(:error) { |message| errors << message }

    expect do
      poll_session.update!(status: :in_progress, started_at: Time.current)
    end.not_to raise_error

    expect(poll_session.reload).to be_in_progress
    expect(errors.join).to include(
      "poll_id=#{poll_session.poll_id}", "poll_session_id=#{poll_session.id}",
      'broadcast="schoolwide_runtime_callback"', 'error_class="StandardError"'
    )
    expect(errors.join).not_to include("학생정보")
  end
end
