require "rails_helper"

RSpec.describe "School Poll definition management", type: :request do
  include Devise::Test::IntegrationHelpers

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

    before { sign_in create(:user, :admin) }

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
    end
  end

  describe "PollOption CRUD" do
    let(:poll) { school_poll }
    let(:contest) { create(:poll_contest, poll: poll, position: 1) }

    before { sign_in create(:user, :admin) }

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

      other_contest = create(:poll_contest, poll: poll, position: 2)
      expect do
        post school_poll_contest_options_path(poll, other_contest),
             params: { poll_option: { number: 1, name: "다른 항목" } }
      end.to change(PollOption, :count).by(1)
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
          status: status
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

  describe "definition UI and existing creation contracts" do
    it "uses election and discussion terminology and keeps empty definitions valid" do
      admin = create(:user, :admin)
      sign_in admin
      election = school_poll(kind: :election)
      discussion = school_poll(kind: :discussion)

      get school_poll_path(election)
      expect(election.poll_contests).to be_empty
      expect(response.body).to include("선거 항목 관리", "선거 항목 추가")
      expect(response.body).not_to include("후보자 추가")

      create(:poll_contest, poll: election, title: "회장 선거", position: 1)
      get school_poll_path(election)
      expect(response.body).to include("후보자 추가")

      create(:poll_contest, poll: discussion, title: "급식 의견", position: 1)
      get school_poll_path(discussion)
      expect(response.body).to include("투표 항목 관리", "선택지 추가")

      expect(election.reload.poll_contests).to be_present
      regular_poll = create(:poll, participant_group: create(:participant_group, :with_participant_slot))
      expect(regular_poll.poll_contests).to be_present
    end
  end
end
