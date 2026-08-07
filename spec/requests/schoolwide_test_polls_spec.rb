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

  it "shows creation and history on source, hides tests from index, and links back from test" do
    source, classrooms = create_source
    admin = create(:user, :admin)
    test_poll = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source, classroom_ids: [classrooms.first.id], actor: admin
    ).call.poll
    sign_in admin

    get school_polls_path
    expect(response.body).to include(source.title)
    expect(response.body).not_to include(test_poll.title)

    get school_poll_path(source)
    expect(response.body).to include("테스트투표 이력", test_poll.title, school_poll_path(test_poll))

    get school_poll_path(test_poll)
    expect(response.body).to include("원본 전교투표로 돌아가기", school_poll_path(source))
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
    post close_school_poll_path(test_poll)

    expect(test_poll.reload).to be_closed
    expect(test_poll.archived_at).to be_present
    expect(session.reload.archived_at).to eq(test_poll.archived_at)
    get results_school_poll_path(test_poll)
    expect(response).to have_http_status(:ok)
    expect(source.reload).to be_draft
    expect(source.started_at).to be_nil
  end
end
