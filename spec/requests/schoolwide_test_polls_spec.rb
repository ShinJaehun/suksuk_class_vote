require "rails_helper"

RSpec.describe "Schoolwide test Polls", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_classroom(school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    classroom
  end

  def create_source
    school = create(:school)
    source = create(:poll, title: "전교어린이회임원선거", school: school,
                           school_managed: true, participant_group: nil)
    contest = create(:poll_contest, poll: source, position: 1)
    create(:poll_option, poll: source, poll_contest: contest, number: 1)
    create(:poll_option, poll: source, poll_contest: contest, number: 2)
    classrooms = 2.times.map { create_classroom(school) }
    classrooms.each do |classroom|
      create(:poll_session, poll: source, classroom: classroom, operator: classroom.teacher)
    end
    [source, classrooms]
  end

  it "allows a same-School manager and global admin, but rejects a regular teacher" do
    [ :manager, :admin ].each do |role|
      source, classrooms = create_source
      actor = if role == :manager
                create(:user).tap do |manager|
                  create(:school_membership, :manager, school: source.school, user: manager)
                end
      else
                create(:user, :admin)
      end
      sign_in actor

      expect do
        post school_poll_test_polls_path(source), params: { classroom_ids: [classrooms.first.id] }
      end.to change(source.test_polls, :count).by(1)
      expect(response).to redirect_to(school_poll_path(source.test_polls.order(:created_at).last))
      sign_out actor
    end

    source, classrooms = create_source
    sign_in create(:user)
    expect do
      post school_poll_test_polls_path(source), params: { classroom_ids: [classrooms.first.id] }
    end.not_to change(Poll, :count)
  end

  it "opens the separate creation page only for authorized actors and an eligible source" do
    source, classrooms = create_source
    manager = create(:user)
    create(:school_membership, :manager, school: source.school, user: manager)

    [manager, create(:user, :admin)].each do |actor|
      sign_in actor
      get new_school_poll_test_poll_path(source)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(classrooms.first.name, classrooms.second.name)
      sign_out actor
    end

    sign_in create(:user)
    get new_school_poll_test_poll_path(source)
    expect(response).not_to have_http_status(:ok)

    sign_in create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: create(:user, :admin)
    ).call.poll
    get new_school_poll_test_poll_path(test_poll)
    expect(response).not_to have_http_status(:ok)

    source.update!(status: :in_progress, started_at: Time.current)
    get new_school_poll_test_poll_path(source)
    expect(response).not_to have_http_status(:ok)
  end

  it "rejects an unstartable source and shows only current assigned Classrooms" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    sign_in admin
    source.poll_contests.first.poll_options.delete_all

    get new_school_poll_test_poll_path(source)
    expect(response).to redirect_to(school_poll_path(source))
    get school_poll_path(source)
    expect(response.body).not_to include(new_school_poll_test_poll_path(source))

    source.poll_contests.first.tap do |contest|
      create(:poll_option, poll: source, poll_contest: contest, number: 1)
      create(:poll_option, poll: source, poll_contest: contest, number: 2)
    end
    get new_school_poll_test_poll_path(source)

    source.current_poll_sessions.each do |session|
      expect(response.body.scan(session.classroom_name_snapshot).size).to eq(1)
    end
  end

  it "hides test Polls from the index and shows them as newest-first Poll history" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    second_test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.second.id], actor: admin
    ).call.poll
    test_poll.update_column(:created_at, 1.hour.ago)
    sign_in admin

    get school_polls_path
    expect(response.body).to include(source.title)
    expect(response.body).not_to include(test_poll.title)

    get school_poll_path(source)
    expect(response.body).to include("테스트투표 만들기", new_school_poll_test_poll_path(source))
    expect(response.body).not_to include("classroom_ids[]")
    page = Nokogiri::HTML(response.body)
    status_check = page.at_css("[data-testid='schoolwide-status-check']").text.squish
    expect(status_check).to include("전교투표 시작", "전교투표를 시작할 수 있습니다.")
    history_rows = page.css("[data-testid^='test-poll-history-']")
    expect(history_rows.map { |row| row["data-testid"] }).to eq(
      ["test-poll-history-#{second_test_poll.id}", "test-poll-history-#{test_poll.id}"]
    )
    expect(history_rows).to all(satisfy { |row| row.text.squish.include?("전교 테스트 선거 준비") })
    expect(page.at_css("[data-testid='test-poll-history-#{test_poll.id}']").to_html)
      .to include(test_poll.title, school_poll_path(test_poll))

    superseded = source.current_poll_sessions.first
    source.update!(
      status: :in_progress,
      started_at: 1.hour.ago
    )
    superseded.update!(
      status: :stopped,
      started_at: 50.minutes.ago,
      stopped_at: 40.minutes.ago
    )
    create(
      :poll_session,
      poll: source,
      classroom: superseded.classroom,
      operator: superseded.operator,
      replacement_of: superseded
    )

    get school_poll_path(source)

    page = Nokogiri::HTML(response.body)
    headings = page.css("section h2").map { |heading| heading.text.strip }
    expect(headings.index("학급 Session")).to be < headings.index("재투표 이력")
    expect(headings.index("재투표 이력")).to be < headings.index("테스트투표 이력")

    get school_poll_path(test_poll)
    expect(response.body).not_to include("테스트투표 만들기")
    expect(response.body).to include("원본 전교투표로 돌아가기", school_poll_path(source))
  end

  it "hides an empty source history and links a closed test Poll result from its history" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    sign_in admin

    get school_poll_path(source)
    expect(response.body).not_to include("테스트투표 이력")

    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    test_poll.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    get school_poll_path(source)
    history_row = Nokogiri::HTML(response.body).at_css("[data-testid='test-poll-history-#{test_poll.id}']")
    expect(history_row.to_html).to include(results_school_poll_path(test_poll), "테스트투표 시작", "테스트투표 종료")
  end

  it "blocks every definition mutation and Classroom assignment on a test Poll" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    contest = test_poll.poll_contests.sole
    option = contest.poll_options.first
    unassigned = create_classroom(source.school)
    sign_in admin

    patch school_poll_path(test_poll), params: { poll: { title: "변조" } }
    expect(test_poll.reload.title).not_to eq("변조")
    expect do
      post school_poll_contests_path(test_poll), params: { poll_contest: { title: "추가" } }
    end.not_to change(test_poll.poll_contests, :count)
    patch school_poll_contest_option_path(test_poll, contest, option),
          params: { poll_option: { name: "변조", number: option.number } }
    expect(option.reload.name).not_to eq("변조")
    expect do
      post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [unassigned.id] }
    end.not_to change(test_poll.poll_sessions, :count)
  end

  it "starts, closes, archives, and shows results through the existing lifecycle without changing source" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    sign_in admin

    get school_poll_path(test_poll)
    status_check = Nokogiri::HTML(response.body).at_css("[data-testid='schoolwide-status-check']").text.squish
    expect(status_check).to include("테스트투표 시작", "테스트투표를 시작할 수 있습니다.")
    expect(status_check).not_to include("전교투표 시작")
    expect(response.body).to include("테스트투표를 시작할까요?")

    post start_school_poll_path(test_poll)

    expect(test_poll.reload).to be_in_progress
    session = test_poll.poll_sessions.sole
    Polls::StartSession.new(actor: session.operator, poll_session: session).call
    session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = session.poll_progress.current_poll_participant
    Polls::CloseSession.new(
      actor: session.operator,
      poll_session: session,
      expected_current_poll_participant_id: current.id
    ).call
    get school_poll_path(test_poll)
    expect(response.body).to include(
      "테스트투표 중단",
      "테스트투표를 중단할까요?",
      "테스트투표 종료",
      "테스트투표를 종료할까요?"
    )
    post close_school_poll_path(test_poll)

    expect(test_poll.reload).to be_closed
    expect(test_poll.archived_at).to be_present
    expect(session.reload.archived_at).to eq(test_poll.archived_at)
    get school_poll_path(test_poll)
    expect(response.body).to include("테스트투표가 종료되었습니다.", "테스트투표 시작", "테스트투표 종료")
    get results_school_poll_path(test_poll)
    expect(response).to have_http_status(:ok)
    get poll_poll_session_path(test_poll, session)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("투표 결과", "테스트")
    expect(source.reload).to be_draft
    expect(source.started_at).to be_nil
  end

  it "uses test lifecycle wording after a test Poll is stopped" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    sign_in admin

    post start_school_poll_path(test_poll)
    post stop_school_poll_path(test_poll)
    get school_poll_path(test_poll)

    expect(response.body).to include("테스트투표가 중단되었습니다.", "테스트투표 시작", "테스트투표 중단")
    expect(response.body).not_to include("전교투표 중단")
  end
end
