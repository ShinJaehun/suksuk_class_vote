require "rails_helper"

RSpec.describe "Classroom Poll definition management", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  let(:operator) { create(:user) }
  let(:school) { create(:school) }
  let(:classroom) do
    create(:school_membership, school: school, user: operator)
    create(:classroom, school: school, teacher: operator).tap { |record| create(:student, classroom: record) }
  end
  let(:poll) { create(:poll, user: operator, school: school, participant_group: nil, school_managed: false) }
  let(:poll_session) { create(:poll_session, poll: poll, classroom: classroom, operator: operator) }

  before { sign_in operator }

  it "edits the title without removing existing definition records and blocks a kind change" do
    contest = poll.default_poll_contest
    option = create(:poll_option, poll: poll, poll_contest: contest)
    poll_session

    patch poll_path(poll), params: { poll: { title: "토론 이름" } }

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(poll.reload.title).to eq("토론 이름")
    patch poll_path(poll), params: { poll: { kind: "debate" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(poll.reload.kind).not_to eq("debate")
    expect(contest.reload).to be_persisted
    expect(option.reload).to be_persisted
  end

  it "allows a kind change with only the automatic empty default Contest" do
    poll_session

    patch poll_path(poll), params: { poll: { kind: "debate" } }

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(poll.reload).to be_debate

    poll.default_poll_contest.update!(title: "토론 주제")
    patch poll_path(poll), params: { poll: { kind: "survey" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(poll.reload).to be_debate
  end

  it "creates, updates, and deletes nested contests and options" do
    poll_session
    get poll_poll_session_path(poll, poll_session)
    expect(response.body).not_to include("1. 기본")
    expect(response.body).to include("투표 항목이 없습니다.")
    expect(response.body).not_to include(">투표 시작<")

    post poll_poll_session_contests_path(poll, poll_session), params: { poll_contest: { title: "새 문항" } }
    contest = poll.poll_contests.order(:position).last
    expect(poll.poll_contests.count).to eq(1)
    expect(contest).to have_attributes(title: "새 문항", position: 1)

    post poll_poll_session_contests_path(poll, poll_session), params: { poll_contest: { title: "둘째 문항" } }
    expect(poll.poll_contests.count).to eq(2)
    expect(poll.poll_contests.order(:position).last).to have_attributes(title: "둘째 문항", position: 2)

    patch poll_poll_session_contest_path(poll, poll_session, contest), params: { poll_contest: { title: "수정 문항" } }
    post poll_poll_session_contest_options_path(poll, poll_session, contest), params: { poll_option: { number: 3, name: "선택" } }
    option = contest.poll_options.sole
    expect(option.poll).to eq(poll)

    patch poll_poll_session_contest_option_path(poll, poll_session, contest, option), params: { poll_option: { number: 4, name: "수정 선택" } }
    expect(option.reload).to have_attributes(number: 4, name: "수정 선택")
    delete poll_poll_session_contest_option_path(poll, poll_session, contest, option)
    expect(option.class.exists?(option.id)).to be(false)
    delete poll_poll_session_contest_path(poll, poll_session, contest)
    expect(contest.class.exists?(contest.id)).to be(false)
  end

  it "edits a replacement draft definition without changing its source Poll" do
    source_contest = poll.default_poll_contest
    source_contest.update!(title: "원본 항목")
    source_option = create(:poll_option, poll: poll, poll_contest: source_contest,
                                         number: 1, name: "원본 후보")
    poll_session.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
    create(:poll_participant, poll: poll, poll_session: poll_session,
                              source_participant_slot: nil, number: 1, name: "학생")
    replacement = Polls::RevoteSession.new(actor: operator, poll_session: poll_session).call.poll_session
    replacement_poll = replacement.poll
    replacement_contest = replacement_poll.default_poll_contest
    replacement_option = replacement_contest.poll_options.sole

    patch poll_path(replacement_poll), params: { poll: { title: "4학년 학급 임원 재선거" } }
    expect(replacement_poll.reload.title).to eq("4학년 학급 임원 재선거")
    expect(poll.reload.title).not_to eq("4학년 학급 임원 재선거")

    patch poll_poll_session_contest_path(replacement_poll, replacement, replacement_contest),
          params: { poll_contest: { title: "수정 항목" } }
    patch poll_poll_session_contest_option_path(replacement_poll, replacement, replacement_contest, replacement_option),
          params: { poll_option: { number: 2, name: "수정 후보" } }
    expect(replacement_contest.reload.title).to eq("수정 항목")
    expect(replacement_option.reload).to have_attributes(number: 2, name: "수정 후보")
    expect(source_contest.reload.title).to eq("원본 항목")
    expect(source_option.reload).to have_attributes(number: 1, name: "원본 후보")

    post poll_poll_session_contests_path(replacement_poll, replacement),
         params: { poll_contest: { title: "추가 항목" } }
    added_contest = replacement_poll.poll_contests.order(:position).last
    post poll_poll_session_contest_options_path(replacement_poll, replacement, added_contest),
         params: { poll_option: { number: 1, name: "추가 선택지" } }
    added_option = added_contest.poll_options.sole
    delete poll_poll_session_contest_option_path(replacement_poll, replacement, added_contest, added_option)
    delete poll_poll_session_contest_path(replacement_poll, replacement, added_contest)
    expect(added_option.class.exists?(added_option.id)).to be(false)
    expect(added_contest.class.exists?(added_contest.id)).to be(false)
  end

  it "rejects replacement definition changes after starting or from an unrelated teacher" do
    source_option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest,
                                         number: 1, name: "원본 후보")
    poll_session.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
    create(:poll_participant, poll: poll, poll_session: poll_session,
                              source_participant_slot: nil)
    replacement = Polls::RevoteSession.new(actor: operator, poll_session: poll_session).call.poll_session
    replacement_poll = replacement.poll
    replacement_contest = replacement_poll.default_poll_contest
    replacement_option = replacement_contest.poll_options.sole
    original_title = replacement_poll.title

    unrelated = create(:user)
    create(:school_membership, school: school, user: unrelated)
    sign_in unrelated
    patch poll_path(replacement_poll), params: { poll: { title: "무단 수정" } }
    patch poll_poll_session_contest_option_path(replacement_poll, replacement, replacement_contest, replacement_option),
          params: { poll_option: { name: "무단 후보 수정" } }
    expect(replacement_poll.reload.title).to eq(original_title)
    expect(replacement_option.reload.name).to eq(source_option.name)

    sign_in operator
    replacement.update!(status: :in_progress, started_at: Time.current)
    patch poll_path(replacement_poll), params: { poll: { title: "시작 후 수정" } }
    patch poll_poll_session_contest_option_path(replacement_poll, replacement, replacement_contest, replacement_option),
          params: { poll_option: { name: "시작 후 후보 수정" } }
    expect(replacement_poll.reload.title).to eq(original_title)
    expect(replacement_option.reload.name).to eq(source_option.name)
  end

  it "blocks changes after the Session starts" do
    poll_session
    poll_session.update!(status: :in_progress, started_at: Time.current)
    original_title = poll.title

    patch poll_path(poll), params: { poll: { title: "차단" } }

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(poll.reload.title).to eq(original_title)
  end

  it "returns not found for an Option nested under another Contest in a safe draft" do
    contest = poll.default_poll_contest
    option = create(:poll_option, poll: poll, poll_contest: contest, name: "원래 이름")
    poll_session
    other_contest = create(:poll_contest, poll: poll, position: 2)

    patch poll_poll_session_contest_option_path(poll, poll_session, other_contest, option),
          params: { poll_option: { name: "위조" } }

    expect(response).to have_http_status(:not_found)
    expect(option.reload.name).to eq("원래 이름")
  end

  it "blocks a non-operator from changing a draft definition" do
    poll_session
    original_title = poll.title
    sign_in create(:user)

    patch poll_path(poll), params: { poll: { title: "위조" } }
    expect(response).to redirect_to(polls_path)
    expect(poll.reload.title).to eq(original_title)
  end

  it "blocks changes to a school-managed draft Session" do
    poll_session
    poll.update!(school_managed: true)
    original_title = poll.title

    patch poll_path(poll), params: { poll: { title: "위조" } }
    expect(response).to have_http_status(:not_found)
    expect(poll.reload.title).to eq(original_title)
  end

  it "shows editable workspace only for a safe classroom draft" do
    poll_session
    option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest)
    get poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("투표 설정", "#{poll.contest_label} 추가", "#{poll.choice_label} 추가", "투표자 명단", "상태점검")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(turbo-frame##{dom_id(poll_session, :contest_list)}))).to be_present
    expect(page.at_css("turbo-frame#school_poll_modal")).to be_present
    expect(page.at_css("dialog")).to be_nil
    workspace_links = [
      page.at_css(%(a[href="#{new_poll_poll_session_contest_path(poll, poll_session)}"])),
      page.at_css(%(a[href="#{edit_poll_poll_session_contest_path(poll, poll_session, poll.default_poll_contest)}"])),
      page.at_css(%(a[href="#{new_poll_poll_session_contest_option_path(poll, poll_session, poll.default_poll_contest)}"])),
      page.at_css(%(a[href="#{edit_poll_poll_session_contest_option_path(poll, poll_session, poll.default_poll_contest, option)}"]))
    ]
    expect(workspace_links).to all(be_present)
    expect(workspace_links.map { |link| link["data-turbo-frame"] }).to all(eq("school_poll_modal"))

    roster_link = page.css("[data-testid='poll-session-roster'] a").find { |link| link.text.include?("투표자 명단 수정") }
    expect(roster_link).to be_present
    expect(roster_link["href"]).to include(
      classroom_students_path(classroom),
      "return_poll_id=#{poll.id}",
      "return_poll_session_id=#{poll_session.id}"
    )
    expect(roster_link["data-turbo-frame"]).to eq("_top")
    expect(page.at_css("[data-testid='poll-session-roster']").text).to include("투표를 시작할 때 이 학급의 활성 학생 명단이 투표자로 확정됩니다.")

    poll.update!(school_managed: true)
    get poll_poll_session_path(poll, poll_session)
    expect(response.body).not_to include('data-testid="poll-session-definition-form"')
  end


  it "renders Contest and Option forms in the existing modal frame with direct HTML fallbacks" do
    poll_session
    contest = poll.default_poll_contest
    option = create(:poll_option, poll: poll, poll_contest: contest, number: 1)

    get new_poll_poll_session_contest_path(poll, poll_session), headers: { "Turbo-Frame" => "school_poll_modal" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(id="school_poll_modal"), poll.contest_label, "취소")

    get edit_poll_poll_session_contest_path(poll, poll_session, contest), headers: { "Turbo-Frame" => "school_poll_modal" }
    expect(response.body).to include(%(id="school_poll_modal"), contest.title, "취소")

    get new_poll_poll_session_contest_option_path(poll, poll_session, contest), headers: { "Turbo-Frame" => "school_poll_modal" }
    page = Nokogiri::HTML(response.body)
    frame = page.at_css("turbo-frame#school_poll_modal")
    expect(frame).to be_present
    expect(frame.text.squish).to include(poll.choice_number_label, "이름", "취소")
    expect(frame.at_css('input[name="poll_option[number]"]')).to be_present
    expect(frame.at_css('input[name="poll_option[name]"]')).to be_present
    submit = frame.at_css('input[type="submit"]')
    expect(submit).to be_present
    expect(submit["value"]).to eq("추가")

    get edit_poll_poll_session_contest_option_path(poll, poll_session, contest, option), headers: { "Turbo-Frame" => "school_poll_modal" }
    expect(response.body).to include(%(id="school_poll_modal"), option.name, option.number.to_s, "취소")

    get new_poll_poll_session_contest_path(poll, poll_session)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(id="school_poll_modal"))
  end

  it "streams Contest create, update, destroy, and inline validation errors" do
    poll_session

    post poll_poll_session_contests_path(poll, poll_session),
         params: { poll_contest: { title: "" } },
         headers: { "Turbo-Frame" => "school_poll_modal" },
         as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(id="school_poll_modal"))

    post poll_poll_session_contests_path(poll, poll_session), params: { poll_contest: { title: "새 항목" } }, as: :turbo_stream
    contest = poll.poll_contests.order(:position).last
    expect(response.body).to include(
      %(action="append" target="#{dom_id(poll_session, :contest_list)}"),
      %(action="update" target="school_poll_modal"),
      %(target="#{dom_id(poll_session, :status_check)}")
    )

    patch poll_poll_session_contest_path(poll, poll_session, contest), params: { poll_contest: { title: "수정 항목" } }, as: :turbo_stream
    expect(contest.reload.title).to eq("수정 항목")
    expect(response.body).to include(%(action="replace" target="#{dom_id(contest)}"), %(target="#{dom_id(poll_session, :status_check)}"))

    delete poll_poll_session_contest_path(poll, poll_session, contest), as: :turbo_stream
    expect(response.body).to include(%(action="remove" target="#{dom_id(contest)}"), %(target="#{dom_id(poll_session, :status_check)}"))
  end

  it "streams Option CRUD and immediately refreshes readiness" do
    poll_session
    contest = poll.default_poll_contest
    first = create(:poll_option, poll: poll, poll_contest: contest, number: 1, name: "첫 후보")

    post poll_poll_session_contest_options_path(poll, poll_session, contest),
         params: { poll_option: { number: 2, name: "" } },
         headers: { "Turbo-Frame" => "school_poll_modal" },
         as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(id="school_poll_modal"))

    post poll_poll_session_contest_options_path(poll, poll_session, contest), params: { poll_option: { number: 2, name: "둘째 후보" } }, as: :turbo_stream
    second = contest.poll_options.find_by!(number: 2)
    expect(response.body).to include(
      %(action="append" target="#{dom_id(contest, :option_list)}"),
      %(action="update" target="school_poll_modal"),
      %(target="#{dom_id(poll_session, :status_check)}"),
      "투표 시작"
    )

    patch poll_poll_session_contest_option_path(poll, poll_session, contest, second), params: { poll_option: { number: 2, name: "수정 후보" } }, as: :turbo_stream
    expect(second.reload.name).to eq("수정 후보")
    expect(response.body).to include(%(action="replace" target="#{dom_id(second)}"))

    delete poll_poll_session_contest_option_path(poll, poll_session, contest, second), as: :turbo_stream
    expect(response.body).to include(%(action="remove" target="#{dom_id(second)}"), %(target="#{dom_id(poll_session, :status_check)}"))
    expect(response.body).not_to include("투표 시작")
    expect(first.reload).to be_persisted
  end

  it "does not show student management after the draft Session" do
    poll_session
    %i[in_progress closed stopped].each do |status|
      poll_session.update!(
        status: status,
        started_at: 1.hour.ago,
        closed_at: (status == :closed ? Time.current : nil),
        stopped_at: (status == :stopped ? Time.current : nil)
      )
      get poll_poll_session_path(poll, poll_session)
      expect(response.body).not_to include("투표자 명단 수정")
    end
  end
end
