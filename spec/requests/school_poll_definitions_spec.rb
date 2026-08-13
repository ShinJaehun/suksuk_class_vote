require "rails_helper"

RSpec.describe "School Poll definition management", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  def school_poll(school: create(:school), kind: :election)
    create(
      :poll,
      school: school,
      school_managed: true,
      participant_group: nil,
      kind: kind
    )
  end

  def manager_for(school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    manager
  end

  def uploaded_photo(filename: "candidate.jpg", content_type: "image/jpeg", contents: "photo")
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.binmode
    file.write(contents)
    file.rewind

    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  describe "authorization and association scope" do
    it "allows global admin and the same-School manager" do
      poll = school_poll

      [create(:user, :admin), manager_for(poll.school)].each do |actor|
        sign_in actor

        expect do
          post school_poll_contests_path(poll),
               params: { poll_contest: { title: "회장 선거" } }
        end.to change(poll.poll_contests, :count).by(1)

        sign_out actor
      end
    end

    it "rejects another School manager, a regular teacher, and a normal Poll" do
      poll = school_poll
      other_manager = manager_for(create(:school))

      [other_manager, create(:user)].each do |actor|
        sign_in actor
        expect do
          post school_poll_contests_path(poll),
               params: { poll_contest: { title: "접근 불가" } }
        end.not_to change(PollContest, :count)
        sign_out actor
      end

      normal_poll = create(:poll, school_managed: false)
      sign_in create(:user, :admin)
      expect do
        post school_poll_contests_path(normal_poll),
             params: { poll_contest: { title: "접근 불가" } }
      end.not_to change(PollContest, :count)
    end

    it "scopes Contest and Option IDs through their parents" do
      poll = school_poll
      other_poll = school_poll(school: poll.school)
      contest = create(:poll_contest, poll: poll, position: 1)
      other_contest = create(:poll_contest, poll: other_poll, position: 1)
      option = create(:poll_option, poll: poll, poll_contest: contest)
      other_option = create(:poll_option, poll: other_poll, poll_contest: other_contest)
      sign_in create(:user, :admin)

      patch school_poll_contest_path(poll, other_contest),
            params: { poll_contest: { title: "조작" } }
      expect(other_contest.reload.title).not_to eq("조작")

      patch school_poll_contest_option_path(poll, contest, other_option),
            params: { poll_option: { number: 9, name: "조작" } }
      expect(other_option.reload.name).not_to eq("조작")

      patch school_poll_contest_option_path(poll, other_contest, option),
            params: { poll_option: { number: 9, name: "조작" } }
      expect(option.reload.name).not_to eq("조작")
    end
  end

  describe "PollContest CRUD" do
    let(:poll) { school_poll }
    let(:admin) { create(:user, :admin) }

    before { sign_in admin }

    it "creates ordered Contests, updates only title, and destroys dependent Options" do
      create(:poll_contest, poll: poll, position: 2)

      post school_poll_contests_path(poll),
           params: { poll_contest: { title: "회장 선거", position: 99 } }
      contest = poll.poll_contests.order(:created_at).last
      expect(contest).to have_attributes(title: "회장 선거", position: 3)

      patch school_poll_contest_path(poll, contest),
            params: { poll_contest: { title: "부회장 선거", position: 1 } }
      expect(contest.reload).to have_attributes(title: "부회장 선거", position: 3)

      option = create(:poll_option, poll: poll, poll_contest: contest)
      expect do
        delete school_poll_contest_path(poll, contest)
      end.to change(PollContest, :count).by(-1)
        .and change(PollOption, :count).by(-1)
      expect(PollOption.exists?(option.id)).to be(false)
    end

    it "renders validation errors without creating an invalid Contest" do
      expect do
        post school_poll_contests_path(poll),
             params: { poll_contest: { title: "" } }
      end.not_to change(PollContest, :count)
      expect(response).to have_http_status(:unprocessable_content)

      post school_poll_contests_path(poll),
           params: { poll_contest: { title: "" } }, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="school_poll_modal"), "poll_contest[title]")
    end

    it "broadcasts the Poll status runtime after every successful Contest change" do
      stream = Turbo::StreamsChannel.send(
        :stream_name_from,
        Polls::BroadcastSchoolwideSessionState.stream_for(poll: poll, user: admin)
      )

      expect do
        post school_poll_contests_path(poll), params: { poll_contest: { title: "방송 항목" } }
      end.to change { broadcasts(stream).size }.by(1)
      contest = poll.poll_contests.find_by!(title: "방송 항목")

      expect do
        patch school_poll_contest_path(poll, contest), params: { poll_contest: { title: "수정 항목" } }
      end.to change { broadcasts(stream).size }.by(1)
      expect do
        delete school_poll_contest_path(poll, contest)
      end.to change { broadcasts(stream).size }.by(1)

      expect(broadcasts(stream).join).to include(
        ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
      )
    end

    it "updates and removes a Contest with Turbo Stream while keeping HTML fallback" do
      post school_poll_contests_path(poll),
           params: { poll_contest: { title: "새 항목" } }, as: :turbo_stream
      contest = poll.poll_contests.find_by!(title: "새 항목")
      expect(response.body).to include(
        %(action="replace" target="contests_poll_#{poll.id}"),
        %(action="update" target="school_poll_modal")
      )

      patch school_poll_contest_path(poll, contest),
            params: { poll_contest: { title: "수정한 항목" } }, as: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(
        %(action="replace" target="poll_contest_#{contest.id}"),
        %(action="update" target="school_poll_modal"),
        "수정한 항목"
      )

      patch school_poll_contest_path(poll, contest),
            params: { poll_contest: { title: "" } }, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="school_poll_modal"), "poll_contest[title]")
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{school_poll_path(poll)}']")["data-turbo-frame"]).to be_nil

      delete school_poll_contest_path(poll, contest), as: :turbo_stream
      expect(response.body).to include(%(action="remove" target="poll_contest_#{contest.id}"))

      html_contest = create(:poll_contest, poll: poll, position: 2)
      patch school_poll_contest_path(poll, html_contest), params: { poll_contest: { title: "HTML 수정" } }
      expect(response).to redirect_to(school_poll_path(poll))
      delete school_poll_contest_path(poll, html_contest)
      expect(response).to redirect_to(school_poll_path(poll))
    end
  end

  describe "PollOption CRUD" do
    let(:admin) { create(:user, :admin) }
    let(:poll) { school_poll }
    let(:contest) { create(:poll_contest, poll: poll, position: 1) }

    before { sign_in admin }

    it "prefills the next Option number for election and non-election Polls" do
      create(:poll_option, poll: poll, poll_contest: contest, number: 2)
      get new_school_poll_contest_option_path(poll, contest)
      expect(Nokogiri::HTML(response.body).at_css("input[name='poll_option[number]']")["value"]).to eq("3")

      survey = school_poll(kind: :survey)
      survey_contest = create(:poll_contest, poll: survey)
      get new_school_poll_contest_option_path(survey, survey_contest)
      expect(Nokogiri::HTML(response.body).at_css("input[name='poll_option[number]']")["value"]).to eq("1")
    end

    it "keeps election Options in two columns and other kinds in one column" do
      create(:poll_option, poll: poll, poll_contest: contest)
      get school_poll_path(poll)
      election_list = Nokogiri::HTML(response.body).at_css("#poll_contest_#{contest.id} .mt-3.grid")
      expect(election_list["class"]).to include("sm:grid-cols-2")
      expect(election_list.text).to include("수정", "삭제")
      expect(response.body).to include(new_school_poll_contest_option_path(poll, contest))

      %i[survey discussion debate].each do |kind|
        other_poll = school_poll(kind: kind)
        other_contest = create(:poll_contest, poll: other_poll)
        create(:poll_option, poll: other_poll, poll_contest: other_contest)
        get school_poll_path(other_poll)
        option_list = Nokogiri::HTML(response.body).at_css("#poll_contest_#{other_contest.id} .mt-3.grid")
        expect(option_list["class"]).not_to include("sm:grid-cols-2")
        expect(option_list.text).to include("수정", "삭제")
        expect(response.body).to include(new_school_poll_contest_option_path(other_poll, other_contest))
      end
    end

    it "creates, updates, and destroys an Option under its Contest" do
      post school_poll_contest_options_path(poll, contest),
           params: { poll_option: { number: 1, name: "홍길동" } }
      option = contest.poll_options.last
      expect(option).to have_attributes(poll: poll, number: 1, name: "홍길동")

      patch school_poll_contest_option_path(poll, contest, option),
            params: { poll_option: { number: 2, name: "김영희" } }
      expect(option.reload).to have_attributes(number: 2, name: "김영희")

      expect do
        delete school_poll_contest_option_path(poll, contest, option)
      end.to change(PollOption, :count).by(-1)
    end

    it "rejects duplicate numbers in one Contest but allows them in another" do
      create(:poll_option, poll: poll, poll_contest: contest, number: 1)

      expect do
        post school_poll_contest_options_path(poll, contest),
             params: { poll_option: { number: 1, name: "중복" } }
      end.not_to change(PollOption, :count)
      expect(response).to have_http_status(:unprocessable_content)

      post school_poll_contest_options_path(poll, contest),
           params: { poll_option: { number: 1, name: "중복" } }, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="school_poll_modal"), "poll_option[number]")

      other_contest = create(:poll_contest, poll: poll, position: 2)
      expect do
        post school_poll_contest_options_path(poll, other_contest),
             params: { poll_option: { number: 1, name: "다른 항목" } }
      end.to change(PollOption, :count).by(1)
    end

    it "updates start issues and actions through Poll-level Option broadcasts" do
      teacher = create(:user)
      create(:school_membership, school: poll.school, user: teacher)
      classroom = create(:classroom, school: poll.school, teacher: teacher)
      create(:student, classroom: classroom)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
      first = create(:poll_option, poll: poll, poll_contest: contest, number: 1)
      stream = Turbo::StreamsChannel.send(
        :stream_name_from,
        Polls::BroadcastSchoolwideSessionState.stream_for(poll: poll, user: admin)
      )
      target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)

      expect do
        post school_poll_contest_options_path(poll, contest),
             params: { poll_option: { number: 2, name: "두 번째 후보" } }
      end.to change { broadcasts(stream).size }.by(1)
      second = contest.poll_options.find_by!(number: 2)
      payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(target) }
      expect(payload).to include("전교투표를 시작할 수 있습니다.", "테스트투표 만들기", "전교투표 시작")
      expect(payload).not_to include("각 투표 항목에 선택지가 2개 이상 필요합니다.")

      expect do
        delete school_poll_contest_option_path(poll, contest, second)
      end.to change { broadcasts(stream).size }.by(1)
      payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(target) }
      expect(payload).to include("각 투표 항목에 선택지가 2개 이상 필요합니다.")
      expect(payload).not_to include(start_school_poll_path(poll), school_poll_test_polls_path(poll))
      expect(first.reload).to be_present
    end

    it "updates and removes an Option with Turbo Stream while keeping HTML fallback" do
      post school_poll_contest_options_path(poll, contest),
           params: { poll_option: { number: 1, name: "새 후보" } }, as: :turbo_stream
      expect(response.body).to include(
        %(action="replace" target="poll_contest_#{contest.id}"),
        %(action="update" target="school_poll_modal"),
        "새 후보"
      )

      option = contest.poll_options.find_by!(name: "새 후보")

      patch school_poll_contest_option_path(poll, contest, option),
            params: { poll_option: { number: 2, name: "수정한 후보" } }, as: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        %(action="replace" target="poll_option_#{option.id}"),
        %(action="update" target="school_poll_modal"),
        "수정한 후보"
      )

      patch school_poll_contest_option_path(poll, contest, option),
            params: { poll_option: { number: nil, name: "" } }, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="school_poll_modal"), "poll_option[name]")
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{school_poll_path(poll)}']")["data-turbo-frame"]).to be_nil

      delete school_poll_contest_option_path(poll, contest, option), as: :turbo_stream
      expect(response.body).to include(%(action="remove" target="poll_option_#{option.id}"))

      html_option = create(:poll_option, poll: poll, poll_contest: contest, number: 3)
      patch school_poll_contest_option_path(poll, contest, html_option),
            params: { poll_option: { number: 4, name: "HTML 후보" } }
      expect(response).to redirect_to(school_poll_path(poll))
      delete school_poll_contest_option_path(poll, contest, html_option)
      expect(response).to redirect_to(school_poll_path(poll))
    end
  end

  describe "Schoolwide Election candidate photos" do
    let(:poll) { school_poll }
    let(:contest) { create(:poll_contest, poll: poll, position: 1) }

    before { sign_in create(:user, :admin) }

    it "shows photo controls and candidate fallback only for Schoolwide Elections" do
      option = create(:poll_option, poll: poll, poll_contest: contest)

      get new_school_poll_contest_option_path(poll, contest)
      expect(response.body).to include(
        "poll_option_photo",
        "candidate-photo-preview",
        "submit-&gt;candidate-photo-preview#submit",
        "turbo:submit-end-&gt;candidate-photo-preview#submitEnd",
        "data-candidate-photo-preview-target=\"submitButton\"",
        "저장 중...",
        "value=\"추가\"",
        "JPG, PNG, WebP",
        "최대 15MB"
      )

      get edit_school_poll_contest_option_path(poll, contest, option)
      expect(response.body).to include("poll_option_photo", "value=\"저장\"")

      get school_poll_path(poll)
      expect(response.body).to include("avatars/", "h-12 w-12", option.name)

      survey = school_poll(kind: :survey)
      survey_contest = create(:poll_contest, poll: survey)
      survey_option = create(:poll_option, poll: survey, poll_contest: survey_contest)
      get new_school_poll_contest_option_path(survey, survey_contest)
      expect(response.body).not_to include("poll_option_photo", "candidate-photo-preview", "최대 15MB")
      get school_poll_path(survey)
      expect(response.body).not_to include("avatars/", "h-12 w-12")
      expect(response.body).to include(survey_option.name)
    end

    it "creates and replaces a photo and requests variant processing" do
      processed_option_ids = []
      allow_any_instance_of(SchoolPollOptionsController)
        .to receive(:process_photo_variants)
        .and_wrap_original do |_method, option|
          processed_option_ids << option.id
          true
        end

      post school_poll_contest_options_path(poll, contest), params: {
        poll_option: {
          number: 1,
          name: "사진 후보",
          photo: uploaded_photo
        }
      }
      option = contest.poll_options.find_by!(number: 1)
      expect(option.photo).to be_attached
      expect(option.photo.filename.to_s).to eq("candidate.jpg")

      patch school_poll_contest_option_path(poll, contest, option), params: {
        poll_option: {
          number: 1,
          name: option.name,
          remove_photo: "1",
          photo: uploaded_photo(filename: "replacement.webp", content_type: "image/webp")
        }
      }
      expect(option.reload.photo.filename.to_s).to eq("replacement.webp")
      expect(processed_option_ids).to eq([ option.id, option.id ])
    end

    it "removes a photo and displays the existing preview before removal" do
      option = create(:poll_option, poll: poll, poll_contest: contest)
      option.photo.attach(io: StringIO.new("photo"), filename: "candidate.png", content_type: "image/png")

      get edit_school_poll_contest_option_path(poll, contest, option)
      expect(response.body).to include("현재 사진", "poll_option_remove_photo", "후보 사진")

      patch school_poll_contest_option_path(poll, contest, option), params: {
        poll_option: { number: option.number, name: option.name, remove_photo: "1" }
      }

      expect(option.reload.photo).not_to be_attached
      get school_poll_path(poll)
      expect(response.body).to include("avatars/")
    end

    it "keeps a saved Option and reports variant processing failure" do
      allow_any_instance_of(SchoolPollOptionsController)
        .to receive(:process_photo_variants)
        .and_return(false)

      post school_poll_contest_options_path(poll, contest), params: {
        poll_option: {
          number: 1,
          name: "변환 실패 후보",
          photo: uploaded_photo
        }
      }

      expect(contest.poll_options.find_by!(number: 1).photo).to be_attached
      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to include("사진 변환에 실패")
    end

    it "rejects invalid and oversized photos without losing an existing attachment" do
      option = create(:poll_option, poll: poll, poll_contest: contest)
      option.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")

      patch school_poll_contest_option_path(poll, contest, option), params: {
        poll_option: {
          number: option.number,
          name: option.name,
          photo: uploaded_photo(filename: "candidate.txt", content_type: "text/plain")
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(option.reload.photo.filename.to_s).to eq("old.jpg")

      patch school_poll_contest_option_path(poll, contest, option), params: {
        poll_option: {
          number: option.number,
          name: option.name,
          photo: uploaded_photo(contents: "a" * (PollOption::MAX_PHOTO_SIZE + 1))
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(option.reload.photo.filename.to_s).to eq("old.jpg")
    end

    it "ignores manipulated photo and removal parameters outside Schoolwide Elections" do
      survey = school_poll(kind: :survey)
      survey_contest = create(:poll_contest, poll: survey)
      survey_option = create(:poll_option, poll: survey, poll_contest: survey_contest)

      post school_poll_contest_options_path(survey, survey_contest), params: {
        poll_option: { number: 99, name: "변조 생성", photo: uploaded_photo }
      }
      expect(survey_contest.poll_options.find_by!(number: 99).photo).not_to be_attached

      patch school_poll_contest_option_path(survey, survey_contest, survey_option), params: {
        poll_option: {
          number: survey_option.number,
          name: "설문 선택지",
          photo: uploaded_photo,
          remove_photo: "1"
        }
      }

      expect(survey_option.reload.photo).not_to be_attached
      expect(survey_option.name).to eq("설문 선택지")

      former_candidate = create(:poll_option, poll: poll, poll_contest: contest)
      former_candidate.photo.attach(
        io: StringIO.new("old"),
        filename: "old.jpg",
        content_type: "image/jpeg"
      )
      poll.update!(kind: :survey)
      patch school_poll_contest_option_path(poll, contest, former_candidate), params: {
        poll_option: {
          number: former_candidate.number,
          name: former_candidate.name,
          photo: uploaded_photo(filename: "new.jpg"),
          remove_photo: "1"
        }
      }
      expect(former_candidate.reload.photo.filename.to_s).to eq("old.jpg")
    end

    it "blocks photo replacement and removal after definition locking" do
      option = create(:poll_option, poll: poll, poll_contest: contest)
      option.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      operator = create(:user)
      create(:school_membership, school: poll.school, user: operator)
      classroom = create(:classroom, school: poll.school, teacher: operator)
      create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator,
        status: :in_progress,
        started_at: Time.current
      )

      patch school_poll_contest_option_path(poll, contest, option), params: {
        poll_option: {
          number: option.number,
          name: option.name,
          remove_photo: "1",
          photo: uploaded_photo(filename: "new.jpg")
        }
      }

      expect(response).to redirect_to(school_poll_path(poll))
      expect(option.reload.photo.filename.to_s).to eq("old.jpg")
    end
  end

  describe "definition locking" do
    let(:poll) { school_poll }
    let!(:contest) { create(:poll_contest, poll: poll, position: 1) }
    let!(:option) { create(:poll_option, poll: poll, poll_contest: contest) }

    before { sign_in create(:user, :admin) }

    it "allows edits with no Sessions or only draft Sessions" do
      expect(poll).to be_definition_editable
      operator = create(:user, name: "담임교사")
      create(:school_membership, school: poll.school, user: operator)
      classroom = create(
        :classroom,
        school: poll.school,
        teacher: operator
      )
      create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator,
        operator_name_snapshot: operator.name
      )
      expect(poll.reload).to be_definition_editable
    end

    it "locks definitions for every non-draft Session status" do
      %i[in_progress closed stopped].each do |status|
        operator = create(:user, name: "#{status} 담임")
        create(:school_membership, school: poll.school, user: operator)
        classroom = create(
          :classroom,
          school: poll.school,
          teacher: operator
        )
        session = create(
          :poll_session,
          poll: poll,
          classroom: classroom,
          operator: operator,
          operator_name_snapshot: operator.name,
          status: status,
          started_at: (1.hour.ago unless status == :draft),
          closed_at: (Time.current if status == :closed),
          stopped_at: (Time.current if status == :stopped)
        )
        expect(poll.reload).not_to be_definition_editable
        session.destroy!
      end
    end

    it "does not create, update, or destroy while locked" do
      create(:poll_participant, poll: poll)

      expect do
        post school_poll_contests_path(poll),
             params: { poll_contest: { title: "추가 불가" } }
      end.not_to change(PollContest, :count)

      patch school_poll_contest_path(poll, contest),
            params: { poll_contest: { title: "수정 불가" } }
      expect(contest.reload.title).not_to eq("수정 불가")

      expect do
        delete school_poll_contest_option_path(poll, contest, option)
      end.not_to change(PollOption, :count)
      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST /school_polls/:id/mock_candidates" do
    let(:poll) { school_poll }
    let(:admin) { create(:user, :admin) }

    it "creates the fixed four Contests and fifty candidates for an admin" do
      sign_in admin

      expect do
        post mock_candidates_school_poll_path(poll)
      end.to change(PollContest, :count).by(4)
        .and change(PollOption, :count).by(50)

      contests = poll.poll_contests.order(:position)
      expect(contests.pluck(:title, :position)).to eq([
        [ "회장", 1 ],
        [ "부회장", 2 ],
        [ "5학년 부회장", 3 ],
        [ "4학년 부회장", 4 ]
      ])
      expect(contests.map { |contest| contest.poll_options.count }).to eq([ 4, 8, 15, 23 ])

      contests.each do |contest|
        options = contest.poll_options.order(:number)
        expect(options.pluck(:number)).to eq((1..options.size).to_a)
        expect(options.pluck(:name)).to eq(
          (1..options.size).map { |number| "#{contest.title} 후보 #{number}" }
        )
        expect(options).to all(have_attributes(poll_id: poll.id, poll_contest_id: contest.id))
        expect(options).to all(satisfy { |option| !option.photo.attached? })
      end

      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:notice]).to eq("테스트 선거 항목 4개와 후보자 50명을 만들었습니다.")
    end

    it "rejects managers, teachers, and unauthenticated users" do
      actors = [ manager_for(poll.school), manager_for(create(:school)), create(:user) ]

      actors.each do |actor|
        sign_in actor
        expect { post mock_candidates_school_poll_path(poll) }
          .not_to change(PollContest, :count)
        sign_out actor
      end

      expect { post mock_candidates_school_poll_path(poll) }
        .not_to change(PollContest, :count)
    end

    it "rejects non-Schoolwide Elections and non-draft Schoolwide Elections" do
      sign_in admin
      invalid_polls = [
        create(:poll, school_managed: false, kind: :election),
        school_poll(kind: :survey),
        school_poll(kind: :discussion),
        school_poll(kind: :debate),
        school_poll.tap { |item| item.update!(status: :in_progress, started_at: Time.current) },
        school_poll.tap do |item|
          item.update!(
            status: :closed,
            started_at: 1.hour.ago,
            closed_at: Time.current
          )
        end
      ]

      invalid_polls.each do |invalid_poll|
        expect { post mock_candidates_school_poll_path(invalid_poll) }
          .not_to change(PollContest, :count)
      end
    end

    it "rejects a locked draft Poll" do
      sign_in admin
      create(:poll_participant, poll: poll)

      expect { post mock_candidates_school_poll_path(poll) }
        .not_to change(PollContest, :count)
      expect(flash[:alert]).to eq("테스트 후보는 초안 상태의 전교 선거에서만 만들 수 있습니다.")
    end

    it "preserves existing definitions and rejects a second request" do
      sign_in admin
      existing_poll = school_poll
      existing_contest = create(:poll_contest, poll: existing_poll, title: "기존 항목")

      expect { post mock_candidates_school_poll_path(existing_poll) }
        .not_to change(PollContest, :count)
      expect(existing_contest.reload.title).to eq("기존 항목")
      expect(flash[:alert]).to eq("기존 선거 항목이나 후보자가 있어 테스트 후보를 만들 수 없습니다.")

      post mock_candidates_school_poll_path(poll)
      expect { post mock_candidates_school_poll_path(poll) }
        .to change(PollContest, :count).by(0)
        .and change(PollOption, :count).by(0)
      expect(poll.poll_contests.count).to eq(4)
      expect(PollOption.where(poll_id: poll.id).count).to eq(50)
    end

    it "rejects an existing PollOption even without a target Poll Contest" do
      sign_in admin
      other_poll = school_poll
      other_contest = create(:poll_contest, poll: other_poll)
      existing_option = create(:poll_option, poll: other_poll, poll_contest: other_contest)
      existing_option.update_column(:poll_id, poll.id)

      expect { post mock_candidates_school_poll_path(poll) }
        .not_to change(PollContest, :count)
      expect(existing_option.reload.poll_id).to eq(poll.id)
    end

    it "rolls back every Contest and candidate when a candidate fails" do
      sign_in admin
      invalid_option = PollOption.new
      invalid_option.errors.add(:base, "저장 실패")
      allow_any_instance_of(PollOption).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
        if method.receiver.name == "부회장 후보 3"
          raise ActiveRecord::RecordInvalid, invalid_option
        end

        method.call(*args, **kwargs)
      end

      expect do
        post mock_candidates_school_poll_path(poll)
      end.to change(PollContest, :count).by(0)
        .and change(PollOption, :count).by(0)
      expect(poll.reload).to be_draft
      expect(flash[:alert]).to eq("저장 실패")
    end

    it "shows the test tool only to admins with an empty editable Election" do
      sign_in admin
      get edit_school_poll_path(poll)

      expect(response.body).to include(
        "관리 편의",
        "테스트 후보 50명 만들기",
        "테스트용 선거 항목 4개와 후보 50명을 사진 없이 생성합니다.",
        "테스트용 선거 항목 4개와 후보 50명을 만들까요?"
      )

      manager = manager_for(poll.school)
      sign_out admin
      sign_in manager
      get school_poll_path(poll)
      expect(response.body).not_to include("테스트 도구", "테스트 후보 50명 만들기")

      teacher = create(:user)
      sign_out manager
      sign_in teacher
      get school_poll_path(poll)
      expect(response).to have_http_status(:not_found)

      sign_out teacher
      sign_in admin
      hidden_polls = [
        school_poll(kind: :survey),
        school_poll.tap { |item| create(:poll_contest, poll: item) },
        school_poll.tap { |item| item.update!(status: :in_progress, started_at: Time.current) }
      ]
      hidden_polls.each do |hidden_poll|
        get school_poll_path(hidden_poll)
        expect(response.body).not_to include("테스트 도구", "테스트 후보 50명 만들기")
      end
    end
  end

  describe "definition UI and existing creation contracts" do
    it "uses election and discussion terminology and keeps empty definitions valid" do
      admin = create(:user, :admin)
      sign_in admin
      election = school_poll(kind: :election)
      discussion = school_poll(kind: :discussion)

      get school_poll_path(election)
      expect(election.poll_contests).to be_empty
      expect(response.body).to include("투표 항목 관리", "투표 항목 추가", "투표 설정")
      expect(response.body).not_to include("선거 항목 관리", "선거 항목 추가", "선거 설정")
      expect(response.body).not_to include("후보자 추가")

      contest = create(:poll_contest, poll: election, title: "회장 선거", position: 1)
      option = create(:poll_option, poll: election, poll_contest: contest)
      get school_poll_path(election)
      expect(response.body).to include("후보자 추가")
      page = Nokogiri::HTML(response.body)
      contest_section = page.css("section").find do |section|
        section.at_css("h2")&.text&.strip == "투표 항목 관리"
      end
      expect(contest_section.to_html).not_to include("선거 항목과 후보자를 관리합니다.", "turbo-confirm")
      modal_paths = [
        new_school_poll_contest_path(election),
        edit_school_poll_contest_path(election, contest),
        new_school_poll_contest_option_path(election, contest),
        edit_school_poll_contest_option_path(election, contest, option)
      ]
      modal_paths.each do |path|
        expect(page.at_css("a[href='#{path}']")["data-turbo-frame"]).to eq("school_poll_modal")
      end

      create(:poll_contest, poll: discussion, title: "급식 의견", position: 1)
      get school_poll_path(discussion)
      expect(response.body).to include("투표 항목 관리", "의견 추가")

      expect(election.reload.poll_contests).to be_present
      regular_poll = create(:poll, participant_group: create(:participant_group, :with_participant_slot))
      expect(regular_poll.poll_contests).to be_present
    end
  end
end
