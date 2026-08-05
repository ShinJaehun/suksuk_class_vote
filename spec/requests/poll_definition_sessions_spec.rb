require "rails_helper"

RSpec.describe "Poll definition sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:school) { create(:school, name: "아라초등학교") }
  let(:teacher) { create(:user, name: "김교사") }

  def active_classroom_for(user, students: 1)
    create(:school_membership, school: school, user: user) unless user.school_membership
    classroom = create(:classroom, school: school, teacher: user)
    students.times { create(:student, classroom: classroom) }
    user.reload
    classroom
  end

  describe "GET /polls/new" do
    it "requires authentication" do
      get new_poll_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows only the active homeroom summary and definition fields" do
      classroom = active_classroom_for(teacher, students: 2)
      sign_in teacher

      get new_poll_path

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("새 학급투표", classroom.formatted_class_label, "담당 교사", "김교사 선생님", "현재 학생", "2명")
      expect(response.body).not_to include("담임 교사")
      expect(page.at_css('[data-testid="poll-kind-selector"]')).to be_present
      expect(page.css('select[name="poll[kind]"] option').map { |node| node["value"] }).to eq(%w[election survey discussion debate])
      expect(response.body).not_to include("번호 표시")
      expect(response.body).not_to include('name="classroom_id"', "poll_contests_attributes", "poll_options_attributes")
      expect(response.body).to include("학급투표 초안 만들기")
    end

    it "does not show the form without an active homeroom or active students" do
      create(:school_membership, school: school, user: teacher)
      sign_in teacher
      get new_poll_path
      expect(response.body).to include("활성 담임 학급이 없어")
      expect(response.body).not_to include("학급투표 초안 만들기")

      sign_out teacher
      empty_teacher = create(:user)
      active_classroom_for(empty_teacher, students: 0)
      sign_in empty_teacher
      get new_poll_path
      expect(response.body).to include("활성 학생이 있는 담임 학급")
      expect(response.body).not_to include("학급투표 초안 만들기")
    end

    it "renders every kind option from Poll labels" do
      active_classroom_for(teacher)
      sign_in teacher
      get new_poll_path

      options = Nokogiri::HTML(response.body).css('[data-testid="poll-kind-selector"] option')
      expect(options.map { |node| [node.text, node["value"]] }).to eq(Poll::ACTIVITY_LABELS.map { |kind, label| [label, kind] })
    end
  end

  describe "POST /polls" do
    it "uses active_classroom, ignores forged input, and creates an empty draft workspace" do
      classroom = active_classroom_for(teacher, students: 2)
      forged = create(:classroom, :with_teacher)
      sign_in teacher

      expect do
        post polls_path, params: { classroom_id: forged.id, poll: { title: "우리 반 토의", kind: "discussion", poll_contests_attributes: { "0" => { title: "위조" } } } }
      end.to change(Poll, :count).by(1).and change(PollSession, :count).by(1).and change(PollContest, :count).by(1).and change(PollOption, :count).by(0)

      poll = Poll.order(:id).last
      session = poll.poll_sessions.sole
      expect(poll).to have_attributes(title: "우리 반 토의", kind: "discussion", status: "draft", school_managed: false, school: school, user: teacher)
      expect(poll.poll_contests.sole.title).to eq("기본")
      expect(session).to have_attributes(classroom: classroom, operator: teacher, status: "draft")
      expect([poll.poll_participants.count, poll.poll_option_tallies.count, poll.poll_contest_tallies.count, poll.poll_events.count]).to all(eq(0))
      expect(response).to redirect_to(poll_poll_session_path(poll, session))
      expect(flash[:notice]).to eq("학급투표 초안을 만들었습니다. 투표 정보를 입력해 주세요.")
    end

    it "preserves the selected kind after validation failure without a preview" do
      active_classroom_for(teacher)
      sign_in teacher
      post polls_path, params: { poll: { title: "", kind: "debate" } }

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css('select[name="poll[kind]"] option[value="debate"][selected]')).to be_present
      expect(response.body).not_to include("번호 표시")
    end
  end
end
