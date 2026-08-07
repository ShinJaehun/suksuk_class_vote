require "rails_helper"

RSpec.describe "PollSession replacement rosters", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_replacement
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                   status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
    create(:poll_participant, poll: poll, poll_session: source,
                              source_participant_slot: nil, number: 1, name: "원본")
    replacement = Polls::RevoteSession.new(actor: teacher, poll_session: source).call.poll_session
    [source, replacement, teacher]
  end

  it "edits only a replacement draft roster atomically and records the source event" do
    source, replacement, teacher = create_replacement
    create(:student, classroom: replacement.classroom, number: 9, name: "학급 학생")
    sign_in teacher

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: {
        participants: {
          "0" => { number: "2", name: "수정" },
          "1" => { number: "3", name: "추가" },
          "2" => { number: "", name: "" }
        }
      }
    }

    expect(response).to redirect_to(poll_poll_session_path(replacement.poll, replacement))
    expect(flash[:notice]).to eq("투표자 명단을 수정했습니다.")
    expect(replacement.poll_participants.order(:number).pluck(:number, :name)).to eq([[2, "수정"], [3, "추가"]])
    expect(source.poll_participants.pluck(:number, :name)).to eq([[1, "원본"]])
    expect(replacement.classroom.students.pluck(:number, :name)).to eq([[9, "학급 학생"]])
    expect(source.poll_events.last).to have_attributes(event_type: "replacement_roster_updated")
    expect(replacement.poll_events).to be_empty
  end

  it "rejects invalid rows without partial saving" do
    _, replacement, teacher = create_replacement
    original = replacement.poll_participants.pluck(:number, :name)
    sign_in teacher

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: { participants: { "0" => { number: "1", name: "" }, "1" => { number: "1", name: "중복" } } }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(replacement.reload.poll_participants.pluck(:number, :name)).to eq(original)
  end

  it "rejects 31 submitted participants and preserves the entire existing roster" do
    _, replacement, teacher = create_replacement
    original = replacement.poll_participants.order(:number).pluck(:number, :name)
    rows = 31.times.to_h do |index|
      [index.to_s, { number: (index + 1).to_s, name: "학생 #{index + 1}" }]
    end
    sign_in teacher

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: { participants: rows }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("투표자는 최대 30명까지 등록할 수 있습니다.")
    expect(replacement.reload.poll_participants.order(:number).pluck(:number, :name)).to eq(original)
  end

  it "rolls back every deletion when creating a submitted participant fails validation" do
    _, replacement, teacher = create_replacement
    original = replacement.poll_participants.order(:number).pluck(:number, :name)
    invalid_record = replacement.poll_participants.first
    allow_any_instance_of(PollParticipant).to receive(:save!)
      .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
    sign_in teacher

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: { participants: { "0" => { number: "2", name: "새 학생" } } }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(replacement.reload.poll_participants.order(:number).pluck(:number, :name)).to eq(original)
  end

  it "rejects a same-school manager from editing or updating a replacement roster" do
    _, replacement, = create_replacement
    original = replacement.poll_participants.order(:number).pluck(:number, :name)
    manager = create(:user)
    create(
      :school_membership,
      :manager,
      school: replacement.classroom.school,
      user: manager
    )
    sign_in manager
    get edit_poll_poll_session_roster_path(replacement.poll, replacement)

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("접근 권한이 없습니다.")

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: { participants: { "0" => { number: "4", name: "권한 확인" } } }
    }

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    expect(replacement.reload.poll_participants.order(:number).pluck(:number, :name)).to eq(original)
  end

  it "allows a global admin to edit and update a replacement roster" do
    _, replacement, = create_replacement
    admin = create(:user, :admin)
    sign_in admin

    get edit_poll_poll_session_roster_path(replacement.poll, replacement)
    expect(response).to have_http_status(:ok)

    patch poll_poll_session_roster_path(replacement.poll, replacement), params: {
      roster: { participants: { "0" => { number: "4", name: "권한 확인" } } }
    }

    expect(response).to redirect_to(poll_poll_session_path(replacement.poll, replacement))
    expect(replacement.reload.poll_participants.pluck(:number, :name)).to eq([[4, "권한 확인"]])
   end

  it "rejects an initial draft, a started replacement, and an unrelated teacher" do
    _, replacement, teacher = create_replacement
    initial = create(:poll_session)
    sign_in teacher
    get edit_poll_poll_session_roster_path(initial.poll, initial)
    expect(response).to redirect_to(polls_path)

    replacement.update!(status: :in_progress, started_at: Time.current)
    get edit_poll_poll_session_roster_path(replacement.poll, replacement)
    expect(response).to redirect_to(polls_path)

    sign_out teacher
    unrelated = create(:user)
    create(:school_membership, school: replacement.classroom.school, user: unrelated)
    sign_in unrelated
    get edit_poll_poll_session_roster_path(replacement.poll, replacement)
    expect(response).to redirect_to(polls_path)
  end
end
