require "rails_helper"

RSpec.describe "Candidates", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /elections/:election_id/candidates/new" do
    it "redirects guests to sign in" do
      election = create(:election)

      get new_election_candidate_path(election)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own election" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      sign_in teacher

      get new_election_candidate_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "does not allow teachers to access another teacher's election" do
      sign_in create(:user)
      election = create(:election)

      get new_election_candidate_path(election)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's election" do
      sign_in create(:user, :admin)
      election = create(:election)

      get new_election_candidate_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "shows the next candidate number" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      sign_in teacher

      get new_election_candidate_path(election)

      expect(response.body).to include("1번 후보를 추가합니다.")
    end

    it "shows the next number after existing candidates" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      create(:candidate, election: election, number: 1)
      sign_in teacher

      get new_election_candidate_path(election)

      expect(response.body).to include("2번 후보를 추가합니다.")
    end

    it "does not allow access after the election starts" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :in_progress)
      sign_in teacher

      get new_election_candidate_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to eq("draft 상태의 선거에서만 후보자를 관리할 수 있습니다.")
    end

    it "does not allow access after the election closes" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :closed)
      sign_in teacher

      get new_election_candidate_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to eq("draft 상태의 선거에서만 후보자를 관리할 수 있습니다.")
    end
  end

  describe "POST /elections/:election_id/candidates" do
    it "allows teachers to create candidates for their own election" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      sign_in teacher

      expect do
        post election_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.to change(Candidate, :count).by(1)

      candidate = Candidate.find_by!(name: "김민준")
      expect(candidate.election).to eq(election)
      expect(candidate.number).to eq(1)
      expect(response).to redirect_to(election_path(election))
    end

    it "assigns candidate numbers on the server" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      create(:candidate, election: election, number: 1)
      sign_in teacher

      post election_candidates_path(election), params: {
        candidate: { name: "이서연", number: 99 }
      }

      candidate = Candidate.find_by!(name: "이서연")
      expect(candidate.number).to eq(2)
    end

    it "does not create candidates with a blank name" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      sign_in teacher

      expect do
        post election_candidates_path(election), params: {
          candidate: { name: "" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보자를 추가할 수 없습니다.")
    end

    it "does not create candidates after the election starts" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :in_progress)
      sign_in teacher

      expect do
        post election_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(election_path(election))
    end

    it "does not create candidates after the election closes" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :closed)
      sign_in teacher

      expect do
        post election_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(election_path(election))
    end
  end

  describe "PATCH /elections/:election_id/candidates/:id" do
    it "allows teachers to update candidate names for their own election" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      candidate = create(:candidate, election: election, name: "이전 이름")
      sign_in teacher

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("새 이름")
      expect(response).to redirect_to(election_path(election))
    end

    it "does not update candidate numbers from params" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      candidate = create(:candidate, election: election, number: 1)
      sign_in teacher

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "번호 유지", number: 99 }
      }

      expect(candidate.reload.number).to eq(1)
    end

    it "does not allow teachers to update another teacher's candidate" do
      sign_in create(:user)
      election = create(:election)
      candidate = create(:candidate, election: election, name: "원래 이름")

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "변경 시도" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to update another teacher's candidate" do
      sign_in create(:user, :admin)
      election = create(:election)
      candidate = create(:candidate, election: election, name: "원래 이름")

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "관리자 수정" }
      }

      expect(candidate.reload.name).to eq("관리자 수정")
      expect(response).to redirect_to(election_path(election))
    end

    it "does not update candidates after the election starts" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :in_progress)
      candidate = create(:candidate, election: election, name: "원래 이름")
      sign_in teacher

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(election_path(election))
    end

    it "does not update candidates after the election closes" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :closed)
      candidate = create(:candidate, election: election, name: "원래 이름")
      sign_in teacher

      patch election_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(election_path(election))
    end
  end

  describe "DELETE /elections/:election_id/candidates/:id" do
    it "allows teachers to delete candidates for their own election" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      candidate = create(:candidate, election: election)
      sign_in teacher

      expect do
        delete election_candidate_path(election, candidate)
      end.to change(Candidate, :count).by(-1)

      expect(response).to redirect_to(election_path(election))
    end

    it "does not renumber remaining candidates after deletion" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      first_candidate = create(:candidate, election: election, number: 1)
      second_candidate = create(:candidate, election: election, number: 2)
      sign_in teacher

      delete election_candidate_path(election, first_candidate)

      expect(second_candidate.reload.number).to eq(2)
    end

    it "does not allow teachers to delete another teacher's candidate" do
      sign_in create(:user)
      election = create(:election)
      candidate = create(:candidate, election: election)

      expect do
        delete election_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to delete another teacher's candidate" do
      sign_in create(:user, :admin)
      election = create(:election)
      candidate = create(:candidate, election: election)

      expect do
        delete election_candidate_path(election, candidate)
      end.to change(Candidate, :count).by(-1)

      expect(response).to redirect_to(election_path(election))
    end

    it "does not delete candidates after the election starts" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :in_progress)
      candidate = create(:candidate, election: election)
      sign_in teacher

      expect do
        delete election_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(election_path(election))
    end

    it "does not delete candidates after the election closes" do
      teacher = create(:user)
      election = create(:election, user: teacher, status: :closed)
      candidate = create(:candidate, election: election)
      sign_in teacher

      expect do
        delete election_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(election_path(election))
    end
  end
end
