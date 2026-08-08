require "rails_helper"

RSpec.describe "School Poll lifecycle controls", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_poll(school:, actor:, status: :draft, test_source: nil)
    create(
      :poll,
      school: school,
      user: actor,
      school_managed: true,
      participant_group: nil,
      test_source_poll: test_source,
      status: status,
      started_at: (1.hour.ago unless status == :draft),
      stopped_at: (Time.current if status == :stopped),
      closed_at: (Time.current if status == :closed),
      archived_at: (Time.current if status == :closed)
    )
  end

  def manager_for(school)
    create(:user).tap do |manager|
      create(:school_membership, :manager, school: school, user: manager)
    end
  end

  it "shows manager deletion only for draft source and deletable test Polls" do
    school = create(:school)
    manager = manager_for(school)
    draft_source = create_poll(school: school, actor: manager)
    closed_source = create_poll(school: school, actor: manager, status: :closed)
    test_poll = create_poll(school: school, actor: manager, test_source: draft_source,
                            status: :stopped)
    sign_in manager

    get edit_school_poll_path(draft_source)
    expect(response.body).to include("전교투표 삭제", school_poll_path(draft_source))
    get edit_school_poll_path(closed_source)
    expect(response.body).not_to include("전교투표 삭제", "전교투표 전체 초기화")
    expect(response.body).to include("정상 종료된 전교투표는 보존")
    # Test Poll은 별도 설정 페이지가 없으므로 삭제 action은 상세 화면에 남는다.
    get school_poll_path(test_poll)
    expect(response.body).to include("테스트투표 삭제", school_poll_path(test_poll))
  end

  it "lets a manager reset their School Poll and delete a draft source subtree" do
    school = create(:school)
    manager = manager_for(school)
    source = create_poll(school: school, actor: manager, status: :stopped)
    child = create_poll(school: school, actor: manager, test_source: source)
    sign_in manager

    post reset_school_poll_path(source), params: { confirmation_title: source.title }
    expect(source.reload).to be_draft
    expect(child.reload).to have_attributes(status: "draft", archived_at: nil)
    delete school_poll_path(source)

    expect(response).to redirect_to(school_polls_path)
    expect(Poll.where(id: [source.id, child.id])).to be_empty
  end

  it "removes one test history entry without deleting its source" do
    school = create(:school)
    manager = manager_for(school)
    source = create_poll(school: school, actor: manager)
    child = create_poll(school: school, actor: manager, test_source: source,
                        status: :closed)
    child.update!(title: "삭제할 테스트투표")
    sign_in manager

    delete school_poll_path(child)

    expect(response).to redirect_to(school_poll_path(source))
    expect(source.reload).to be_persisted
    get school_poll_path(source)
    expect(response.body).not_to include(child.title)
  end

  it "requires an exact title before admin force deletion" do
    admin = create(:user, :admin)
    poll = create_poll(school: create(:school), actor: admin, status: :in_progress)
    sign_in admin

    get edit_school_poll_path(poll)
    expect(response.body).to include("영구 삭제", "확인을 위해 전교투표 이름을 입력하세요.")
    delete school_poll_path(poll), params: { confirmation_title: "wrong" }
    expect(poll.reload).to be_persisted

    delete school_poll_path(poll), params: { confirmation_title: poll.title }
    expect(response).to redirect_to(school_polls_path)
    expect(Poll.exists?(poll.id)).to be(false)
  end

  it "stops unfinished child tests when the source closes and blocks restart/reset" do
    school = create(:school)
    manager = manager_for(school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)

    source = create_poll(school: school, actor: manager)

    contest = create(:poll_contest, poll: source)
    create(:poll_option, poll: source, poll_contest: contest, number: 1)
    create(:poll_option, poll: source, poll_contest: contest, number: 2)

    source_session = create(:poll_session, poll: source, classroom: classroom,
                                           operator: teacher)

    expect(
      Polls::StartSchoolwidePoll.new(poll: source, actor: manager).call
    ).to be_success
    expect(
      Polls::StartSession.new(actor: teacher, poll_session: source_session).call
    ).to be_success

    source_session.reload.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = source_session.poll_progress.current_poll_participant
    expect(
      Polls::CloseSession.new(
        actor: teacher,
        poll_session: source_session,
        expected_current_poll_participant_id: current.id
      ).call
    ).to be_success

    source.reload

    child = create_poll(school: school, actor: manager, test_source: source)
    child_contest = create(:poll_contest, poll: child)
    child_option = create(:poll_option, poll: child, poll_contest: child_contest)
    child_session = create(:poll_session, poll: child, classroom: classroom, operator: teacher,
                                          status: :closed, started_at: 40.minutes.ago,
                                          closed_at: 20.minutes.ago)
    create(:poll_option_tally, poll: child, poll_session: child_session,
                               poll_option: child_option, votes_count: 4)
    second_teacher = create(:user)
    create(:school_membership, school: school, user: second_teacher)
    second_classroom = create(:classroom, school: school, teacher: second_teacher)
    unfinished_session = create(:poll_session, poll: child, classroom: second_classroom,
                                               operator: second_teacher)
    sign_in manager

    post close_school_poll_path(source)

    expect(source.reload).to be_closed
    expect(child.reload).to have_attributes(status: "stopped", archived_at: source.closed_at)
    expect(child_session.reload).to have_attributes(status: "closed", archived_at: source.closed_at)
    expect(unfinished_session.reload).to have_attributes(status: "stopped",
                                                         archived_at: source.closed_at)
    get school_poll_path(child)
    expect(response.body).to include("테스트투표가 중단되었습니다.")
    status_counts = Nokogiri::HTML(response.body).at_css(
      "##{ActionView::RecordIdentifier.dom_id(child, :schoolwide_status_counts)}"
    )
    expect(status_counts.css("dt").map { |label| label.text.strip }).not_to include("중단")
    expect(response.body).to include(results_school_poll_path(child))
    expect(response.body).not_to include("테스트투표 시작", "전교투표 전체 초기화")
    get results_school_poll_path(child)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("4표")
    post start_school_poll_path(child)
    expect(child.reload).to be_stopped
    post reset_school_poll_path(child), params: { confirmation_title: child.title }
    expect(child.reload).to be_stopped
  end
end
