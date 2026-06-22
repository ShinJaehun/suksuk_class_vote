require "rails_helper"

RSpec.describe "Admin school election candidates", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/school_elections/:school_election_id/school_election_contests/:school_election_contest_id/school_election_candidates/new" do
    it "redirects guests to sign in" do
      school_election, contest = create_school_election_with_contest

      get new_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      school_election, contest = create_school_election_with_contest
      sign_in create(:user)

      get new_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest)

      expect(response).to redirect_to(polls_path)
    end

    it "shows the candidate creation form to admins" do
      school_election, contest = create_school_election_with_contest
      sign_in create(:user, :admin)

      get new_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보 추가")
      expect(response.body).to include(school_election.title)
      expect(response.body).to include(contest.title)
      expect(response.body).to include("기호")
      expect(response.body).to include("후보 이름")
      expect(response.body).to include("학년/반")
    end
  end

  describe "POST /admin/school_elections/:school_election_id/school_election_contests/:school_election_contest_id/school_election_candidates" do
    it "creates a candidate under the contest for admins" do
      school_election, contest = create_school_election_with_contest
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_contest_school_election_candidates_path(school_election, contest), params: {
          school_election_candidate: {
            number: 1,
            name: "김회장",
            grade_class_label: "6학년 1반"
          }
        }
      end.to change(contest.school_election_candidates, :count).by(1)

      expect(response).to redirect_to(admin_school_election_path(school_election))
      candidate = contest.school_election_candidates.find_by!(number: 1)
      expect(candidate).to have_attributes(name: "김회장", grade_class_label: "6학년 1반")
    end

    it "shows validation errors without creating a duplicate candidate number in the same contest" do
      school_election, contest = create_school_election_with_contest
      create(:school_election_candidate, school_election_contest: contest, number: 1)
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_contest_school_election_candidates_path(school_election, contest), params: {
          school_election_candidate: {
            number: 1,
            name: "중복 후보",
            grade_class_label: "6학년 2반"
          }
        }
      end.not_to change(contest.school_election_candidates, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보를 등록할 수 없습니다.")
      expect(response.body).to include("중복 후보")
      expect(response.body).to include("6학년 2반")
    end

    it "allows the same candidate number in different contests" do
      school_election = create(:school_election)
      first_contest = create(:school_election_contest, school_election: school_election, position: 1)
      second_contest = create(:school_election_contest, school_election: school_election, position: 2)
      create(:school_election_candidate, school_election_contest: first_contest, number: 1)
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_contest_school_election_candidates_path(school_election, second_contest), params: {
          school_election_candidate: {
            number: 1,
            name: "다른 항목 후보",
            grade_class_label: "5학년 1반"
          }
        }
      end.to change(second_contest.school_election_candidates, :count).by(1)
    end

    it "does not allow teachers to create candidates" do
      school_election, contest = create_school_election_with_contest
      sign_in create(:user)

      expect do
        post admin_school_election_school_election_contest_school_election_candidates_path(school_election, contest), params: {
          school_election_candidate: {
            number: 1,
            name: "차단 후보",
            grade_class_label: "6학년 1반"
          }
        }
      end.not_to change(SchoolElectionCandidate, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "does not create a candidate under a contest from another school election" do
      school_election = create(:school_election)
      other_school_election, other_contest = create_school_election_with_contest
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_contest_school_election_candidates_path(school_election, other_contest), params: {
          school_election_candidate: {
            number: 1,
            name: "잘못된 소속 후보",
            grade_class_label: "6학년 1반"
          }
        }
      end.not_to change(SchoolElectionCandidate, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/school_elections/:school_election_id/school_election_contests/:school_election_contest_id/school_election_candidates/:id/edit" do
    it "redirects guests to sign in" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest)

      get edit_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest)
      sign_in create(:user)

      get edit_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate)

      expect(response).to redirect_to(polls_path)
    end

    it "shows the candidate edit form to admins" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest, number: 1, name: "김후보", grade_class_label: "6학년 1반")
      sign_in create(:user, :admin)

      get edit_admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보 수정")
      expect(response.body).to include("김후보")
      expect(response.body).to include("6학년 1반")
    end

    it "does not show a candidate through another contest" do
      school_election = create(:school_election)
      first_contest = create(:school_election_contest, school_election: school_election, position: 1)
      second_contest = create(:school_election_contest, school_election: school_election, position: 2)
      candidate = create(:school_election_candidate, school_election_contest: first_contest)
      sign_in create(:user, :admin)

      get edit_admin_school_election_school_election_contest_school_election_candidate_path(school_election, second_contest, candidate)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/school_elections/:school_election_id/school_election_contests/:school_election_contest_id/school_election_candidates/:id" do
    it "updates a candidate for admins" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest, number: 1, name: "김후보", grade_class_label: "6학년 1반")
      sign_in create(:user, :admin)

      patch admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate), params: {
        school_election_candidate: {
          number: 2,
          name: "이후보",
          grade_class_label: "6학년 2반"
        }
      }

      expect(response).to redirect_to(admin_school_election_path(school_election))
      expect(candidate.reload).to have_attributes(number: 2, name: "이후보", grade_class_label: "6학년 2반")
    end

    it "shows validation errors without changing a candidate to a duplicate number in the same contest" do
      school_election, contest = create_school_election_with_contest
      create(:school_election_candidate, school_election_contest: contest, number: 1)
      candidate = create(:school_election_candidate, school_election_contest: contest, number: 2, name: "기존 후보", grade_class_label: "6학년 2반")
      sign_in create(:user, :admin)

      patch admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate), params: {
        school_election_candidate: {
          number: 1,
          name: "중복 수정 후보",
          grade_class_label: "6학년 3반"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보를 수정할 수 없습니다.")
      expect(response.body).to include("중복 수정 후보")
      expect(response.body).to include("6학년 3반")
      expect(candidate.reload).to have_attributes(number: 2, name: "기존 후보", grade_class_label: "6학년 2반")
    end

    it "does not allow teachers to update candidates" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest)
      sign_in create(:user)

      patch admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate), params: {
        school_election_candidate: {
          number: 2,
          name: "차단 수정 후보",
          grade_class_label: "6학년 2반"
        }
      }

      expect(response).to redirect_to(polls_path)
      expect(candidate.reload.name).not_to eq("차단 수정 후보")
    end

    it "does not update a candidate through another school election contest" do
      school_election, contest = create_school_election_with_contest
      other_school_election, other_contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: other_contest, name: "원래 후보")
      sign_in create(:user, :admin)

      patch admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate), params: {
        school_election_candidate: {
          number: 2,
          name: "잘못된 수정 후보",
          grade_class_label: "6학년 2반"
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(candidate.reload.name).to eq("원래 후보")
    end
  end

  describe "DELETE /admin/school_elections/:school_election_id/school_election_contests/:school_election_contest_id/school_election_candidates/:id" do
    it "destroys a candidate for admins" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest)
      sign_in create(:user, :admin)

      expect do
        delete admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate)
      end.to change(SchoolElectionCandidate, :count).by(-1)

      expect(response).to redirect_to(admin_school_election_path(school_election))
    end

    it "does not allow teachers to destroy candidates" do
      school_election, contest = create_school_election_with_contest
      candidate = create(:school_election_candidate, school_election_contest: contest)
      sign_in create(:user)

      expect do
        delete admin_school_election_school_election_contest_school_election_candidate_path(school_election, contest, candidate)
      end.not_to change(SchoolElectionCandidate, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "does not destroy a candidate through another contest" do
      school_election = create(:school_election)
      first_contest = create(:school_election_contest, school_election: school_election, position: 1)
      second_contest = create(:school_election_contest, school_election: school_election, position: 2)
      candidate = create(:school_election_candidate, school_election_contest: first_contest)
      sign_in create(:user, :admin)

      expect do
        delete admin_school_election_school_election_contest_school_election_candidate_path(school_election, second_contest, candidate)
      end.not_to change(SchoolElectionCandidate, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  def create_school_election_with_contest
    school_election = create(:school_election)
    contest = create(:school_election_contest, school_election: school_election, title: "회장", position: 1)

    [ school_election, contest ]
  end
end
