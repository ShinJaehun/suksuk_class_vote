require "rails_helper"

RSpec.describe "PollSession stale recovery", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_running_schoolwide_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, :manager, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: 1.hour.ago)
    participant = create(:poll_participant, poll: poll, poll_session: session, number: 1, name: "학생")
    create(:poll_progress, poll: poll, poll_session: session, current_poll_participant: participant)
    [poll, session, teacher]
  end

  it "recovers deleted teacher and ballot frames after reset" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, old_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{old_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]
    expect(ballot_frame.at_css("[data-poll-session-terminal]")).to be_nil
    get operation_url
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(
      "turbo-frame#teacher_progress_poll_session_#{old_session.id}"
    )).to be_present

    result = Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    expect(result).to be_success
    expect(PollSession.exists?(old_session.id)).to be(false)
    expect(poll.poll_sessions.sole).to be_draft
    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("전교투표가 초기화되어", "내 투표 목록으로 돌아가기")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
      expect(page.at_css("a[href='#{polls_path}']")).to be_present
      expect(page.at_css("form")).to be_nil
    end
  end

  it "keeps invalid, mismatched, and unauthorized stale requests unavailable" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    get operation_frame_poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:not_found)

    get operation_url.sub("recovery_token=", "recovery_token=invalid")
    expect(response).to have_http_status(:not_found)

    recovery_token = Rack::Utils.parse_nested_query(URI.parse(operation_url).query).fetch("recovery_token")
    other_poll = create(:poll, school: poll.school, school_managed: true, participant_group: nil)
    get operation_frame_poll_poll_session_path(other_poll, old_session, recovery_token: recovery_token)
    expect(response).to have_http_status(:not_found)

    sign_out teacher
    sign_in create(:user)
    get operation_url
    expect(response).to have_http_status(:not_found)
  end

  it "recovers stale frames after the reset Poll and replacement Session restart" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, old_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{old_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]

    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call
    replacement = poll.poll_sessions.sole
    poll.update!(status: :in_progress, started_at: Time.current)
    replacement.update!(status: :in_progress, started_at: Time.current)

    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("전교투표가 초기화되어")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
    end
  end
end
