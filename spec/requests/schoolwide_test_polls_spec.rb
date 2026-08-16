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
                           school_managed: true)
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
        post school_poll_test_polls_path(source)
      end.to change(source.test_polls, :count).by(1)
      test_poll = source.test_polls.order(:created_at).last
      expect(response).to redirect_to(school_poll_path(test_poll))
      expect(test_poll.current_poll_sessions.count).to eq(source.current_poll_sessions.count)
      expect(test_poll.current_poll_sessions.map(&:classroom)).to match_array(source.current_poll_sessions.map(&:classroom))
      expect(source.reload).to be_draft
      sign_out actor
    end

    source, classrooms = create_source
    sign_in create(:user)
    expect do
      post school_poll_test_polls_path(source)
    end.not_to change(Poll, :count)
  end

  it "renders the independently cloned candidate photo instead of a fallback avatar" do
    source, = create_source
    source_option = source.poll_options.order(:number).first
    source_option.update!(name: "사진 후보")
    source_option.photo.attach(
      io: StringIO.new("same candidate image"),
      filename: "candidate.jpg",
      content_type: "image/jpeg"
    )
    admin = create(:user, :admin)
    sign_in admin

    post school_poll_test_polls_path(source)
    test_poll = source.test_polls.order(:created_at).last
    test_option = test_poll.poll_options.find_by!(number: source_option.number)

    expect(test_option.photo).to be_attached
    expect(test_option.photo.blob_id).not_to eq(source_option.photo.blob_id)
    expect(test_option.photo.blob.checksum).to eq(source_option.photo.blob.checksum)

    get school_poll_path(test_poll)
    image = Nokogiri::HTML(response.body).at_css("img[alt='사진 후보 후보 사진']")
    expect(image).to be_present
    expect(image["src"]).not_to include("avatars/")
  end

  it "posts creation from status check and rejects an unstartable source" do
    source, = create_source
    admin = create(:user, :admin)
    sign_in admin
    get school_poll_path(source)
    create_link = Nokogiri::HTML(response.body).at_css("a[href='#{school_poll_test_polls_path(source)}']")
    expect(create_link).to be_present
    expect(create_link["data-turbo-method"]).to eq("post")

    source.poll_contests.first.poll_options.delete_all
    get school_poll_path(source)
    expect(response.body).not_to include(school_poll_test_polls_path(source))

    expect { post school_poll_test_polls_path(source) }.not_to change(source.test_polls, :count)
    expect(response).to redirect_to(school_poll_path(source))
  end

  it "hides test Polls from the index and shows them as newest-first Poll history" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    second_test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    test_poll.update_column(:created_at, 1.hour.ago)
    sign_in admin

    get school_polls_path
    expect(response.body).to include(source.title)
    expect(response.body).not_to include(test_poll.title)

    get school_poll_path(source)
    expect(response.body).to include("테스트투표 만들기", school_poll_test_polls_path(source))
    page = Nokogiri::HTML(response.body)
    status_check = page.at_css("[data-testid='schoolwide-status-check']").text.squish
    expect(status_check).to include("전교투표 시작", "전교투표를 시작할 수 있습니다.")
    history_rows = page.css("[data-testid^='test-poll-history-']")
    expect(history_rows.map { |row| row["data-testid"] }).to eq(
      ["test-poll-history-#{second_test_poll.id}", "test-poll-history-#{test_poll.id}"]
    )
    expect(history_rows).to all(satisfy { |row| row.text.squish.include?("전교 선거 테스트 준비") })
    expect(history_rows).to all(satisfy { |row| row.text.squish.include?("2개 학급") })
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
    expect(headings.index("학급 세션")).to be < headings.index("재투표 이력")
    expect(headings.index("재투표 이력")).to be < headings.index("테스트투표 이력")

    get school_poll_path(test_poll)
    expect(response.body).not_to include("테스트투표 만들기")
    expect(response.body).to include(
      "원본 전교투표로 돌아가기",
      school_poll_path(source),
      "테스트투표 삭제",
      "원본 전교투표에는 영향을 주지 않습니다."
    )
    page = Nokogiri::HTML(response.body)
    overview = page.at_css("##{ActionView::RecordIdentifier.dom_id(test_poll, :school_overview)}")
    expect(overview.text).not_to include("전교투표 목록으로 돌아가기", "원본 전교투표로 돌아가기")
    expect(page.text.scan("원본 전교투표로 돌아가기").size).to eq(1)
    delete_button = page.at_css(
      "form[action='#{school_poll_path(test_poll)}'] button[data-turbo-confirm]"
    )
    expect(delete_button).to be_present
    expect(delete_button["data-turbo-confirm"]).to include("영구 삭제할까요?")
  end

  it "hides an empty source history and links a closed test Poll result from its history" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    sign_in admin

    get school_poll_path(source)
    expect(response.body).not_to include("테스트투표 이력")

    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    test_poll.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    get school_poll_path(source)
    history_row = Nokogiri::HTML(response.body).at_css("[data-testid='test-poll-history-#{test_poll.id}']")
    expect(history_row.to_html).to include(results_school_poll_path(test_poll), "시작", "종료")
    expect(history_row.to_html).not_to include("테스트투표 시작", "테스트투표 종료")
  end

  it "keeps definition immutable while allowing independent same-School assignment" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    contest = test_poll.poll_contests.sole
    option = contest.poll_options.first
    additional = create_classroom(source.school)
    other_school_classroom = create_classroom(create(:school))
    sign_in admin

    get school_poll_path(test_poll)
    page = Nokogiri::HTML(response.body)
    expect(response.body).to include("배정 가능 학급", "4학년 전체", "배정 현황", "배정 학급", "배정 투표 인원")
    sessions_workspace = page.at_css("##{ActionView::RecordIdentifier.dom_id(test_poll, :sessions)}")
    assignable_grade = sessions_workspace.at_css("details[data-testid='school-poll-assignable-grade-classrooms']")
    expect(assignable_grade).to be_present
    expect(assignable_grade.at_css("summary").text.squish).to include("4학년 전체", "+", "−")
    expect(assignable_grade["data-controller"]).to eq("classroom-group-picker")
    expect(assignable_grade.text.squish).to include(
      "#{additional.grade}학년 #{additional.formatted_class_label}",
      "담당 #{additional.teacher.name}",
      "투표자 1명"
    )
    expect(assignable_grade.text.squish).not_to include("학생 1명")
    expect(sessions_workspace.text.squish).to include("배정 학급 2", "배정 투표 인원 2", "배정된 학급 세션")
    expect(classrooms).to all(satisfy { |classroom| sessions_workspace.text.include?(classroom.name) })
    classroom_checkboxes = page.css("input[name='classroom_ids[]']")
    expect(classroom_checkboxes.map { |checkbox| checkbox["value"].to_i }).to contain_exactly(additional.id)
    expect(classroom_checkboxes).to all(satisfy { |checkbox| checkbox["checked"].nil? })
    expect(classroom_checkboxes).to all(satisfy { |checkbox| checkbox["data-classroom-group-picker-target"] == "item" })
    expect(response.body).not_to include(other_school_classroom.name)

    patch school_poll_path(test_poll), params: { poll: { title: "변조" } }
    expect(test_poll.reload.title).not_to eq("변조")
    expect do
      post school_poll_contests_path(test_poll), params: { poll_contest: { title: "추가" } }
    end.not_to change(test_poll.poll_contests, :count)
    patch school_poll_contest_option_path(test_poll, contest, option),
          params: { poll_option: { name: "변조", number: option.number } }
    expect(option.reload.name).not_to eq("변조")

    expect do
      post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [additional.id] }
    end.to change(test_poll.poll_sessions, :count).by(1)
    expect(test_poll.current_poll_sessions.map(&:classroom)).to include(additional)
    get school_poll_path(test_poll)
    page = Nokogiri::HTML(response.body)
    expect(response.body).to include(
      "#{additional.grade}학년 #{additional.formatted_class_label}",
      "배정된 학급 세션",
      "4학년 배정 해제",
      "배정 해제"
    )
    expect(response.body).not_to include(test_poll.current_poll_sessions.find_by!(classroom: additional).classroom_name_snapshot)
    assigned_session = test_poll.current_poll_sessions.find_by!(classroom: classrooms.first)
    grade_form = page.at_css(
      "form[action='#{destroy_grade_school_poll_poll_sessions_path(test_poll, grade: assigned_session.classroom.grade)}']"
    )
    session_form = page.at_css("form[action='#{school_poll_poll_session_path(test_poll, assigned_session)}']")
    expect(grade_form["data-turbo-confirm"]).to be_nil
    expect(session_form["data-turbo-confirm"]).to be_nil
    expect(page.css("input[name='classroom_ids[]']").map { |checkbox| checkbox["value"].to_i })
      .to be_empty

    expect do
      post school_poll_poll_sessions_path(test_poll),
           params: { classroom_ids: [other_school_classroom.id] },
           as: :turbo_stream
    end.not_to change(test_poll.poll_sessions, :count)
    expect(response).to redirect_to(school_poll_path(test_poll))
    expect(flash[:alert]).to include("다른 학교의 학급은 배정할 수 없습니다.")
    follow_redirect!
    expect(response.body).to include(
      "다른 학교의 학급은 배정할 수 없습니다."
    )
    expect do
      post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [classrooms.first.id] }
    end.not_to change(test_poll.poll_sessions, :count)

    another_eligible = create_classroom(source.school)
    test_poll.update!(status: :in_progress, started_at: Time.current)
    expect do
      post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [another_eligible.id] }
    end.not_to change(test_poll.poll_sessions, :count)
  end

  it "updates overview, status, and Session workspace through Turbo assignment and unassignment" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(source_poll: source, actor: admin).call.poll
    additional = create_classroom(source.school)
    sign_in admin
    targets = %i[school_overview status_report sessions].map do |prefix|
      ActionView::RecordIdentifier.dom_id(test_poll, prefix)
    end

    post school_poll_poll_sessions_path(test_poll),
         params: { classroom_ids: [additional.id] },
         as: :turbo_stream
    targets.each { |target| expect(response.body).to include(%(target="#{target}")) }
    session = test_poll.poll_sessions.find_by!(classroom: additional)

    delete school_poll_poll_session_path(test_poll, session), as: :turbo_stream
    expect(test_poll.poll_sessions.reload.count).to eq(classrooms.size)
    targets.each { |target| expect(response.body).to include(%(target="#{target}")) }

    post school_poll_poll_sessions_path(test_poll),
         params: { classroom_ids: [additional.id] }
    delete destroy_grade_school_poll_poll_sessions_path(test_poll, grade: classrooms.first.grade),
           as: :turbo_stream
    expect(test_poll.poll_sessions.reload).to be_empty
    targets.each { |target| expect(response.body).to include(%(target="#{target}")) }

    other_poll = Polls::CreateSchoolwideTestPoll.new(source_poll: source, actor: admin).call.poll
    other_session = other_poll.poll_sessions.first
    expect do
      delete school_poll_poll_session_path(test_poll, other_session)
    end.not_to change(other_poll.poll_sessions, :count)

    post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [classrooms.first.id] }
    assigned = test_poll.poll_sessions.reload.sole
    test_poll.update!(status: :in_progress, started_at: Time.current)
    expect do
      delete school_poll_poll_session_path(test_poll, assigned)
    end.not_to change(test_poll.poll_sessions, :count)
  end

  it "keeps source and test Session composition independent after cloning" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(source_poll: source, actor: admin).call.poll
    additional = create_classroom(source.school)
    sign_in admin

    source_session = source.poll_sessions.find_by!(classroom: classrooms.first)
    test_session = test_poll.poll_sessions.find_by!(classroom: classrooms.first)
    delete school_poll_poll_session_path(source, source_session)
    expect(test_poll.poll_sessions.where(id: test_session.id)).to exist

    source_session_ids = source.poll_session_ids
    delete school_poll_poll_session_path(test_poll, test_session)
    expect(source.reload.poll_session_ids).to match_array(source_session_ids)

    post school_poll_poll_sessions_path(test_poll), params: { classroom_ids: [additional.id] }
    expect(test_poll.poll_sessions.find_by(classroom: additional)).to be_present
    expect(source.poll_sessions.find_by(classroom: additional)).to be_nil

    get school_poll_path(test_poll)
    expect(response.body).to include(classrooms.second.name, additional.name)
  end

  it "starts, closes, archives, and shows results through the existing lifecycle without changing source" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    sign_in admin

    get school_poll_path(test_poll)
    status_check = Nokogiri::HTML(response.body).at_css("[data-testid='schoolwide-status-check']").text.squish
    expect(status_check).to include("테스트투표 시작", "테스트투표를 시작할 수 있습니다.")
    expect(status_check).not_to include("전교투표 시작")
    expect(response.body).to include("테스트투표를 시작할까요?")

    extra_session = test_poll.poll_sessions.find_by!(classroom: classrooms.second)
    delete school_poll_poll_session_path(test_poll, extra_session)

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
    page = Nokogiri::HTML(response.body)
    status_report = page.at_css("[data-testid='schoolwide-status-check']")
    status_actions = status_report.at_css("[data-testid='schoolwide-status-actions']")
    expect(status_actions.at_css("a[href='#{close_school_poll_path(test_poll)}']")).to be_present
    expect(status_actions.at_css("a[href='#{stop_school_poll_path(test_poll)}']")).to be_nil
    expect(response.body).to include(
      "테스트투표 종료",
      "테스트투표를 종료할까요?"
    )
    expect(response.body).not_to include("테스트투표 중단", "테스트투표를 중단할까요?")
    post close_school_poll_path(test_poll)

    expect(test_poll.reload).to be_closed
    expect(test_poll.archived_at).to be_present
    expect(session.reload.archived_at).to eq(test_poll.archived_at)
    get school_poll_path(test_poll)
    lifecycle_times = Nokogiri::HTML(response.body).at_css("[data-testid='school-poll-lifecycle-times']").text
    expect(response.body).to include("테스트투표가 종료되었습니다.")
    expect(lifecycle_times).to include("시작", "종료")
    expect(lifecycle_times).not_to include("테스트투표")
    get results_school_poll_path(test_poll)
    expect(response).to have_http_status(:ok)

    session_detail_path = poll_poll_session_path(test_poll, session, from: "school_poll")
    session_results_path = results_poll_poll_session_path(test_poll, session, from: "school_poll")
    get session_detail_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("결과 집계 보기", session_results_path)
    expect(response.body).not_to include('data-testid="poll-session-results"')

    get session_results_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "#{test_poll.title} 결과 집계",
      "투표 결과 인쇄",
      'data-testid="poll-session-results"',
      'data-testid="poll-session-printable-results"'
    )
    expect(source.reload).to be_draft
    expect(source.started_at).to be_nil
  end

  it "uses test lifecycle wording after a test Poll is stopped" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, actor: admin
    ).call.poll
    sign_in admin

    post start_school_poll_path(test_poll)
    post stop_school_poll_path(test_poll)
    get school_poll_path(test_poll)

    lifecycle_times = Nokogiri::HTML(response.body).at_css("[data-testid='school-poll-lifecycle-times']").text
    expect(response.body).to include("테스트투표가 중단되었습니다.")
    expect(lifecycle_times).to include("시작", "중단")
    expect(lifecycle_times).not_to include("테스트투표", "전교투표")
  end
end
