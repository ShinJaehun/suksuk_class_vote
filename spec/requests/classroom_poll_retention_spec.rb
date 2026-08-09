require "rails_helper"

RSpec.describe "Classroom Poll retention", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_target(status: :draft, operator: nil)
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    operator ||= teacher
    create(:school_membership, school: school, user: operator) unless operator.school_membership
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: operator,
                                    status: status,
                                    started_at: (1.hour.ago unless status == :draft),
                                    closed_at: (Time.current if status == :closed),
                                    stopped_at: (Time.current if status == :stopped))
    [poll, session, teacher]
  end

  it "shows delete for draft/stopped/closed, archive for closed, and neither while running or archived" do
    %i[draft stopped closed in_progress].each do |status|
      poll, session, teacher = create_target(status: status)
      sign_in teacher
      get poll_poll_session_path(poll, session)
      expect(response.body).not_to include("투표 삭제")
      expect(response.body.include?("보관")).to eq(status == :closed)
      get edit_poll_path(poll)
      expect(response).to have_http_status(:ok)
      expect(response.body.include?("학급투표 삭제")).to eq(status != :in_progress)

      sign_out teacher
    end

    poll, session, teacher = create_target(status: :closed)
    archive_time = Time.current
    poll.update!(archived_at: archive_time)
    session.update!(archived_at: archive_time)
    sign_in teacher
    get poll_poll_session_path(poll, session)
    expect(response.body).not_to include(archive_poll_path(poll))
    get results_poll_poll_session_path(poll, session)
    expect(response).to have_http_status(:ok)
    get edit_poll_path(poll)
    expect(response.body).not_to include("학급투표 삭제")
  end

  it "archives Poll and Session, removes it from active list, and keeps it in archive" do
    poll, session, teacher = create_target(status: :closed)
    sign_in teacher

    post archive_poll_path(poll)

    expect(response).to redirect_to(poll_poll_session_path(poll, session))
    expect(session.reload.archived_at).to eq(poll.reload.archived_at)
    get polls_path
    expect(response.body).not_to include(poll.title)
    get archived_polls_path
    expect(response.body).to include(poll.title)

    delete poll_path(poll)
    expect(Poll.exists?(poll.id)).to be(true)
  end

  it "shows an archived Schoolwide Session to its operator instead of only the Poll owner" do
    school = create(:school)
    owner = create(:user)
    operator = create(:user)
    create(:school_membership, school: school, user: owner)
    create(:school_membership, school: school, user: operator)
    classroom = create(:classroom, school: school, teacher: operator)
    archived_at = Time.current

    poll = create(
      :poll,
      user: owner,
      school: school,
      school_managed: true,
      participant_group: nil,
      status: :closed,
      started_at: 1.hour.ago,
      closed_at: archived_at,
      archived_at: archived_at
    )

    session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :closed,
      started_at: 1.hour.ago,
      closed_at: archived_at,
      archived_at: archived_at
    )

    sign_in operator
    get archived_polls_path

    expect(response.body).to include(poll.title)
    expect(response.body).to include(poll_poll_session_path(poll, session))

    sign_out operator
    sign_in owner
    get archived_polls_path

    expect(response.body).not_to include(poll_poll_session_path(poll, session))
  end

  it "allows operator, Classroom teacher, and admin to delete but rejects a same-School manager" do
    [ :operator, :teacher, :admin ].each do |role|
      operator = create(:user)
      poll, _, teacher = create_target(operator: operator)
      actor = { operator: operator, teacher: teacher, admin: create(:user, :admin) }.fetch(role)
      sign_in actor
      delete poll_path(poll)
      expect(Poll.exists?(poll.id)).to be(false)
      sign_out actor
    end

    poll, session, = create_target
    manager = create(:user)
    create(:school_membership, :manager, school: poll.school, user: manager)
    sign_in manager
    delete poll_path(poll)
    expect(session.reload).to be_persisted
  end

  it "rejects deletion of an in-progress classroom Poll and a Schoolwide Poll" do
    poll, session, teacher = create_target(status: :in_progress)
    sign_in teacher
    delete poll_path(poll)
    expect(session.reload).to be_in_progress

    schoolwide = create(:poll, school: create(:school), school_managed: true, participant_group: nil)
    sign_out teacher
    sign_in create(:user, :admin)
    delete poll_path(schoolwide)
    expect(schoolwide.reload).to be_persisted
  end
end
