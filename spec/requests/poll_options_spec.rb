require "rails_helper"

RSpec.describe "PollOptions", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /polls/:poll_id/poll_options/new" do
    it "redirects guests to sign in" do
      poll = create(:poll)

      get new_poll_poll_option_path(poll)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "does not allow teachers to access another teacher's poll" do
      sign_in create(:user)
      poll = create(:poll)

      get new_poll_poll_option_path(poll)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's poll" do
      sign_in create(:user, :admin)
      poll = create(:poll)

      get new_poll_poll_option_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보자 추가")
    end

    it "shows the next poll_option number" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response.body).to include("1번 후보자를 추가합니다.")
      expect(response.body).to include("후보자 이름")
    end

    it "shows the next number after existing poll_options" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      create(:poll_option, poll: poll, number: 1)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response.body).to include("2번 후보자를 추가합니다.")
    end

    it "uses discussion choice labels" do
      teacher = create(:user)
      poll = create(:poll, :discussion, user: teacher)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response.body).to include("의견 추가")
      expect(response.body).to include("1번 의견을 추가합니다.")
      expect(response.body).to include(">의견</label>")
      expect(response.body).not_to include("후보자 이름")
    end

    it "does not allow access after the poll starts" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :in_progress)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("draft 상태의 투표에서만 후보자를 관리할 수 있습니다.")
    end

    it "does not allow access after the poll closes" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :closed)
      sign_in teacher

      get new_poll_poll_option_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("draft 상태의 투표에서만 후보자를 관리할 수 있습니다.")
    end
  end

  describe "POST /polls/:poll_id/poll_options" do
    it "allows teachers to create poll_options for their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      sign_in teacher

      expect do
        post poll_poll_options_path(poll), params: {
          poll_option: { name: "김민준" }
        }
      end.to change(PollOption, :count).by(1)

      poll_option = PollOption.find_by!(name: "김민준")
      expect(poll_option.poll).to eq(poll)
      expect(poll_option.number).to eq(1)
      expect(response).to redirect_to(poll_path(poll))
    end

    it "assigns poll_option numbers on the server" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      create(:poll_option, poll: poll, number: 1)
      sign_in teacher

      post poll_poll_options_path(poll), params: {
        poll_option: { name: "이서연", number: 99 }
      }

      poll_option = PollOption.find_by!(name: "이서연")
      expect(poll_option.number).to eq(2)
    end

    it "does not create poll_options with a blank name" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      sign_in teacher

      expect do
        post poll_poll_options_path(poll), params: {
          poll_option: { name: "" }
        }
      end.not_to change(PollOption, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보자를 추가할 수 없습니다.")
    end

    it "uses discussion labels in create failures and notices" do
      teacher = create(:user)
      poll = create(:poll, :discussion, user: teacher)
      sign_in teacher

      post poll_poll_options_path(poll), params: {
        poll_option: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("의견을 추가할 수 없습니다.")

      post poll_poll_options_path(poll), params: {
        poll_option: { name: "점심시간 연장" }
      }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("의견을 추가했습니다.")
    end

    it "does not create poll_options after the poll starts" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :in_progress)
      sign_in teacher

      expect do
        post poll_poll_options_path(poll), params: {
          poll_option: { name: "김민준" }
        }
      end.not_to change(PollOption, :count)

      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not create poll_options after the poll closes" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :closed)
      sign_in teacher

      expect do
        post poll_poll_options_path(poll), params: {
          poll_option: { name: "김민준" }
        }
      end.not_to change(PollOption, :count)

      expect(response).to redirect_to(poll_path(poll))
    end
  end

  describe "PATCH /polls/:poll_id/poll_options/:id" do
    it "allows teachers to update poll_option names for their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      poll_option = create(:poll_option, poll: poll, name: "이전 이름")
      sign_in teacher

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "새 이름" }
      }

      expect(poll_option.reload.name).to eq("새 이름")
      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not update poll_option numbers from params" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      poll_option = create(:poll_option, poll: poll, number: 1)
      sign_in teacher

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "번호 유지", number: 99 }
      }

      expect(poll_option.reload.number).to eq(1)
    end

    it "does not allow teachers to update another teacher's poll_option" do
      sign_in create(:user)
      poll = create(:poll)
      poll_option = create(:poll_option, poll: poll, name: "원래 이름")

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "변경 시도" }
      }

      expect(poll_option.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to update another teacher's poll_option" do
      sign_in create(:user, :admin)
      poll = create(:poll)
      poll_option = create(:poll_option, poll: poll, name: "원래 이름")

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "관리자 수정" }
      }

      expect(poll_option.reload.name).to eq("관리자 수정")
      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not update poll_options after the poll starts" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :in_progress)
      poll_option = create(:poll_option, poll: poll, name: "원래 이름")
      sign_in teacher

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "새 이름" }
      }

      expect(poll_option.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not update poll_options after the poll closes" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :closed)
      poll_option = create(:poll_option, poll: poll, name: "원래 이름")
      sign_in teacher

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "새 이름" }
      }

      expect(poll_option.reload.name).to eq("원래 이름")
      expect(response).to redirect_to(poll_path(poll))
    end

    it "uses discussion labels in edit failures and notices" do
      teacher = create(:user)
      poll = create(:poll, :discussion, user: teacher)
      poll_option = create(:poll_option, poll: poll, number: 1, name: "이전 의견")
      sign_in teacher

      get edit_poll_poll_option_path(poll, poll_option)

      expect(response.body).to include("의견 수정")
      expect(response.body).to include("1번 의견입니다.")
      expect(response.body).to include(">의견</label>")

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("의견을 수정할 수 없습니다.")

      patch poll_poll_option_path(poll, poll_option), params: {
        poll_option: { name: "새 의견" }
      }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("의견을 수정했습니다.")
    end
  end

  describe "DELETE /polls/:poll_id/poll_options/:id" do
    it "allows teachers to delete poll_options for their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      poll_option = create(:poll_option, poll: poll)
      sign_in teacher

      expect do
        delete poll_poll_option_path(poll, poll_option)
      end.to change(PollOption, :count).by(-1)

      expect(response).to redirect_to(poll_path(poll))
    end

    it "uses discussion labels in destroy notices" do
      teacher = create(:user)
      poll = create(:poll, :discussion, user: teacher)
      poll_option = create(:poll_option, poll: poll)
      sign_in teacher

      delete poll_poll_option_path(poll, poll_option)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("의견을 삭제했습니다.")
    end

    it "does not renumber remaining poll_options after deletion" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      first_poll_option = create(:poll_option, poll: poll, number: 1)
      second_poll_option = create(:poll_option, poll: poll, number: 2)
      sign_in teacher

      delete poll_poll_option_path(poll, first_poll_option)

      expect(second_poll_option.reload.number).to eq(2)
    end

    it "does not allow teachers to delete another teacher's poll_option" do
      sign_in create(:user)
      poll = create(:poll)
      poll_option = create(:poll_option, poll: poll)

      expect do
        delete poll_poll_option_path(poll, poll_option)
      end.not_to change(PollOption, :count)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to delete another teacher's poll_option" do
      sign_in create(:user, :admin)
      poll = create(:poll)
      poll_option = create(:poll_option, poll: poll)

      expect do
        delete poll_poll_option_path(poll, poll_option)
      end.to change(PollOption, :count).by(-1)

      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not delete poll_options after the poll starts" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :in_progress)
      poll_option = create(:poll_option, poll: poll)
      sign_in teacher

      expect do
        delete poll_poll_option_path(poll, poll_option)
      end.not_to change(PollOption, :count)

      expect(response).to redirect_to(poll_path(poll))
    end

    it "does not delete poll_options after the poll closes" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :closed)
      poll_option = create(:poll_option, poll: poll)
      sign_in teacher

      expect do
        delete poll_poll_option_path(poll, poll_option)
      end.not_to change(PollOption, :count)

      expect(response).to redirect_to(poll_path(poll))
    end
  end
end
