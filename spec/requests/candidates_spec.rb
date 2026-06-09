require "rails_helper"

RSpec.describe "Candidates", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /polls/:poll_id/candidates/new" do
    it "redirects guests to sign in" do
      election = create(:poll)

      get new_poll_candidate_path(election)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "does not allow teachers to access another teacher's election" do
      sign_in create(:user)
      election = create(:poll)

      get new_poll_candidate_path(election)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's election" do
      sign_in create(:user, :admin)
      election = create(:poll)

      get new_poll_candidate_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "shows the next candidate number" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response.body).to include("1번 후보자를 추가합니다.")
      expect(response.body).to include("후보자 이름")
    end

    it "shows the next number after existing candidates" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      create(:candidate, poll: election, number: 1)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response.body).to include("2번 후보자를 추가합니다.")
    end

    it "uses discussion choice labels" do
      teacher = create(:user)
      election = create(:poll, :discussion, user: teacher)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response.body).to include("의견 추가")
      expect(response.body).to include("1번 의견을 추가합니다.")
      expect(response.body).to include(">의견</label>")
      expect(response.body).not_to include("후보자 이름")
    end

    it "does not allow access after the election starts" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :in_progress)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to eq("draft 상태의 투표에서만 후보자를 관리할 수 있습니다.")
    end

    it "does not allow access after the election closes" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :closed)
      sign_in teacher

      get new_poll_candidate_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to eq("draft 상태의 투표에서만 후보자를 관리할 수 있습니다.")
    end
  end

  describe "POST /polls/:poll_id/candidates" do
    it "allows teachers to create candidates for their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      sign_in teacher

      expect do
        post poll_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.to change(Candidate, :count).by(1)

      candidate = Candidate.find_by!(name: "김민준")
      expect(candidate.poll).to eq(election)
      expect(candidate.number).to eq(1)
      expect(response).to redirect_to(poll_path(election))
    end

    it "assigns candidate numbers on the server" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      create(:candidate, poll: election, number: 1)
      sign_in teacher

      post poll_candidates_path(election), params: {
        candidate: { name: "이서연", number: 99 }
      }

      candidate = Candidate.find_by!(name: "이서연")
      expect(candidate.number).to eq(2)
    end

    it "does not create candidates with a blank name" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      sign_in teacher

      expect do
        post poll_candidates_path(election), params: {
          candidate: { name: "" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보자를 추가할 수 없습니다.")
    end

    it "uses discussion labels in create failures and notices" do
      teacher = create(:user)
      election = create(:poll, :discussion, user: teacher)
      sign_in teacher

      post poll_candidates_path(election), params: {
        candidate: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("의견을 추가할 수 없습니다.")

      post poll_candidates_path(election), params: {
        candidate: { name: "점심시간 연장" }
      }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("의견을 추가했습니다.")
    end

    it "does not create candidates after the election starts" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :in_progress)
      sign_in teacher

      expect do
        post poll_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(poll_path(election))
    end

    it "does not create candidates after the election closes" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :closed)
      sign_in teacher

      expect do
        post poll_candidates_path(election), params: {
          candidate: { name: "김민준" }
        }
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(poll_path(election))
    end
  end

  describe "PATCH /polls/:poll_id/candidates/:id" do
    it "allows teachers to update candidate names for their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      candidate = create(:candidate, poll: election, name: "이전 이름")
      sign_in teacher

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("새 이름")
      expect(response).to redirect_to(poll_path(election))
    end

    it "does not update candidate numbers from params" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      candidate = create(:candidate, poll: election, number: 1)
      sign_in teacher

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "번호 유지", number: 99 }
      }

      expect(candidate.reload.number).to eq(1)
    end

    it "does not allow teachers to update another teacher's candidate" do
      sign_in create(:user)
      election = create(:poll)
      candidate = create(:candidate, poll: election, name: "원래 이름")

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "변경 시도" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to update another teacher's candidate" do
      sign_in create(:user, :admin)
      election = create(:poll)
      candidate = create(:candidate, poll: election, name: "원래 이름")

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "관리자 수정" }
      }

      expect(candidate.reload.name).to eq("관리자 수정")
      expect(response).to redirect_to(poll_path(election))
    end

    it "does not update candidates after the election starts" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :in_progress)
      candidate = create(:candidate, poll: election, name: "원래 이름")
      sign_in teacher

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(poll_path(election))
    end

    it "does not update candidates after the election closes" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :closed)
      candidate = create(:candidate, poll: election, name: "원래 이름")
      sign_in teacher

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "새 이름" }
      }

      expect(candidate.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(poll_path(election))
    end

    it "uses discussion labels in edit failures and notices" do
      teacher = create(:user)
      election = create(:poll, :discussion, user: teacher)
      candidate = create(:candidate, poll: election, number: 1, name: "이전 의견")
      sign_in teacher

      get edit_poll_candidate_path(election, candidate)

      expect(response.body).to include("의견 수정")
      expect(response.body).to include("1번 의견입니다.")
      expect(response.body).to include(">의견</label>")

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("의견을 수정할 수 없습니다.")

      patch poll_candidate_path(election, candidate), params: {
        candidate: { name: "새 의견" }
      }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("의견을 수정했습니다.")
    end
  end

  describe "DELETE /polls/:poll_id/candidates/:id" do
    it "allows teachers to delete candidates for their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      candidate = create(:candidate, poll: election)
      sign_in teacher

      expect do
        delete poll_candidate_path(election, candidate)
      end.to change(Candidate, :count).by(-1)

      expect(response).to redirect_to(poll_path(election))
    end

    it "uses discussion labels in destroy notices" do
      teacher = create(:user)
      election = create(:poll, :discussion, user: teacher)
      candidate = create(:candidate, poll: election)
      sign_in teacher

      delete poll_candidate_path(election, candidate)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("의견을 삭제했습니다.")
    end

    it "does not renumber remaining candidates after deletion" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      first_candidate = create(:candidate, poll: election, number: 1)
      second_candidate = create(:candidate, poll: election, number: 2)
      sign_in teacher

      delete poll_candidate_path(election, first_candidate)

      expect(second_candidate.reload.number).to eq(2)
    end

    it "does not allow teachers to delete another teacher's candidate" do
      sign_in create(:user)
      election = create(:poll)
      candidate = create(:candidate, poll: election)

      expect do
        delete poll_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to delete another teacher's candidate" do
      sign_in create(:user, :admin)
      election = create(:poll)
      candidate = create(:candidate, poll: election)

      expect do
        delete poll_candidate_path(election, candidate)
      end.to change(Candidate, :count).by(-1)

      expect(response).to redirect_to(poll_path(election))
    end

    it "does not delete candidates after the election starts" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :in_progress)
      candidate = create(:candidate, poll: election)
      sign_in teacher

      expect do
        delete poll_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(poll_path(election))
    end

    it "does not delete candidates after the election closes" do
      teacher = create(:user)
      election = create(:poll, user: teacher, status: :closed)
      candidate = create(:candidate, poll: election)
      sign_in teacher

      expect do
        delete poll_candidate_path(election, candidate)
      end.not_to change(Candidate, :count)

      expect(response).to redirect_to(poll_path(election))
    end
  end
end
