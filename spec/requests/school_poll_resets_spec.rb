require "rails_helper"

RSpec.describe "School Poll reset", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_target
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    [poll, session, school]
  end

  it "shows the danger area to global admin and the same-School manager" do
    poll, _, school = create_target
    admin = create(:user, :admin)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)

    sign_in admin
    get edit_school_poll_path(poll)
    expect(response.body).to include("전교투표 초기화", "confirmation_title")

    sign_out admin
    sign_in manager
    get edit_school_poll_path(poll)
    expect(response.body).to include("전교투표 초기화", "confirmation_title")
  end

  it "allows a same-School manager and rejects a regular teacher" do
    poll, session, school = create_target
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)

    sign_in manager
    post reset_school_poll_path(poll), params: { confirmation_title: poll.title }
    expect(PollSession.exists?(session.id)).to be(false)

    poll, session, = create_target
    sign_out manager
    sign_in create(:user)
    post reset_school_poll_path(poll), params: { confirmation_title: poll.title }
    expect(PollSession.exists?(session.id)).to be(true)
  end

  it "does nothing when confirmation title differs" do
    poll, session, = create_target
    sign_in create(:user, :admin)

    post reset_school_poll_path(poll), params: { confirmation_title: "다른 이름" }

    expect(response).to redirect_to(school_poll_path(poll))
    expect(flash[:alert]).to eq("전교투표 이름이 일치하지 않아 초기화를 실행하지 않았습니다.")
    expect(PollSession.exists?(session.id)).to be(true)
  end

  it "resets with an exact title and reports the prepared Session count" do
    poll, old_session, = create_target
    sign_in create(:user, :admin)

    post reset_school_poll_path(poll), params: { confirmation_title: poll.title }

    expect(response).to redirect_to(school_poll_path(poll))
    expect(flash[:notice]).to eq("전교투표를 초기화했습니다. 학급 투표 1개를 새로 준비했습니다.")
    expect(PollSession.exists?(old_session.id)).to be(false)
    expect(poll.poll_sessions.count).to eq(1)
  end

  it "logs reset exceptions without their raw messages" do
    poll, = create_target
    sign_in create(:user, :admin)
    messages = []
    allow(Polls::ResetSchoolwidePoll).to receive(:new).and_raise(
      RuntimeError, "민감한 DB 값"
    )
    allow(Rails.logger).to receive(:error) { |message| messages << message }

    post reset_school_poll_path(poll), params: { confirmation_title: poll.title }

    expect(response).to redirect_to(school_poll_path(poll))
    expect(flash[:alert]).to eq("전교투표를 초기화하지 못했습니다. 다시 시도해 주세요.")
    expect(messages.sole).to include(
      "[schoolwide_poll_reset]", "poll_id=#{poll.id}", 'error_class="RuntimeError"'
    )
    expect(messages.sole).not_to include("민감한 DB 값")
  end

  it "does not reset a regular classroom Poll through the School Poll route" do
    poll = create(:poll)
    sign_in create(:user, :admin)

    expect do
      post reset_school_poll_path(poll), params: { confirmation_title: poll.title }
    end.not_to change(PollSession, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "hides and rejects reset for closed or archived Schoolwide Polls" do
    [ :closed, :archived ].each do |state|
      poll, session, = create_target
      poll.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current,
                   archived_at: (Time.current if state == :archived))
      session.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current,
                      archived_at: poll.archived_at)
      sign_in create(:user, :admin)

      get edit_school_poll_path(poll)
      expect(response.body).not_to include("전교투표 초기화")
      expect(response.body).not_to include(%(action="#{reset_school_poll_path(poll)}"))
      expect(response.body).not_to include("영구 삭제")
      expect(response.body).not_to include("confirmation_title")
      expect(response.body).to include(
        "정상 종료된 전교투표는 보존되며 초기화하거나 삭제할 수 없습니다."
      )
      post reset_school_poll_path(poll), params: { confirmation_title: poll.title }
      expect(session.reload).to be_persisted
      sign_out :user
    end
  end
end
