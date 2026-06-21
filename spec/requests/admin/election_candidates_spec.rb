require "rails_helper"
require "tempfile"

RSpec.describe "Admin election candidates", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/elections/:election_id/contests/:election_contest_id/candidates/new" do
    it "redirects guests to sign in" do
      election, contest = create_election_with_contest

      get new_admin_election_election_contest_election_candidate_path(election, contest)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      election, contest = create_election_with_contest
      sign_in create(:user)

      get new_admin_election_election_contest_election_candidate_path(election, contest)

      expect(response).to redirect_to(dashboard_path)
    end

    it "shows the candidate creation form to admins" do
      election, contest = create_election_with_contest
      sign_in create(:user, :admin)

      get new_admin_election_election_contest_election_candidate_path(election, contest)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보 등록")
      expect(response.body).to include(election.title)
      expect(response.body).to include(contest.title)
      expect(response.body).to include("기호")
      expect(response.body).to include("후보 이름")
      expect(response.body).to include("소속")
    end
  end

  describe "POST /admin/elections/:election_id/contests/:election_contest_id/candidates" do
    it "creates a candidate under the contest for admins" do
      election, contest = create_election_with_contest
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_contest_election_candidates_path(election, contest), params: {
          election_candidate: {
            number: 1,
            name: "김회장",
            affiliation_label: "6학년 1반"
          }
        }
      end.to change(contest.election_candidates, :count).by(1)

      expect(response).to redirect_to(admin_election_path(election))
      candidate = contest.election_candidates.find_by!(number: 1)
      expect(candidate).to have_attributes(name: "김회장", affiliation_label: "6학년 1반")
    end

    it "attaches a photo when creating a candidate for a draft election" do
      election, contest = create_election_with_contest
      sign_in create(:user, :admin)

      post admin_election_election_contest_election_candidates_path(election, contest), params: {
        election_candidate: {
          number: 1,
          name: "사진 후보",
          affiliation_label: "6학년 1반",
          photo: uploaded_photo(filename: "candidate.jpg", content_type: "image/jpeg")
        }
      }

      candidate = contest.election_candidates.find_by!(number: 1)
      expect(response).to redirect_to(admin_election_path(election))
      expect(candidate.photo).to be_attached
      expect(candidate.photo.content_type).to eq("image/jpeg")
    end

    it "shows validation errors without creating a duplicate candidate number in the same contest" do
      election, contest = create_election_with_contest
      create(:election_candidate, election_contest: contest, number: 1)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_contest_election_candidates_path(election, contest), params: {
          election_candidate: {
            number: 1,
            name: "중복 후보",
            affiliation_label: "6학년 2반"
          }
        }
      end.not_to change(contest.election_candidates, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보를 등록할 수 없습니다.")
      expect(response.body).to include("중복 후보")
      expect(response.body).to include("6학년 2반")
    end

    it "does not allow teachers to create candidates" do
      election, contest = create_election_with_contest
      sign_in create(:user)

      expect do
        post admin_election_election_contest_election_candidates_path(election, contest), params: {
          election_candidate: {
            number: 1,
            name: "차단 후보",
            affiliation_label: "6학년 1반"
          }
        }
      end.not_to change(ElectionCandidate, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "does not create candidates after the election starts" do
      election, contest = create_election_with_contest
      election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_contest_election_candidates_path(election, contest), params: {
          election_candidate: {
            number: 1,
            name: "차단 후보",
            affiliation_label: "6학년 1반"
          }
        }
      end.not_to change(ElectionCandidate, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
    end

    it "does not create candidates after the election is closed" do
      election, contest = create_election_with_contest
      election.update!(status: :closed)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_contest_election_candidates_path(election, contest), params: {
          election_candidate: {
            number: 1,
            name: "차단 후보",
            affiliation_label: "6학년 1반"
          }
        }
      end.not_to change(ElectionCandidate, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
    end

    it "does not create a candidate under a contest from another election" do
      election = create(:election)
      _other_election, other_contest = create_election_with_contest
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_contest_election_candidates_path(election, other_contest), params: {
          election_candidate: {
            number: 1,
            name: "잘못된 소속 후보",
            affiliation_label: "6학년 1반"
          }
        }
      end.not_to change(ElectionCandidate, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/elections/:election_id/contests/:election_contest_id/candidates/:id/edit" do
    it "shows the candidate edit form to admins" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "김후보", affiliation_label: "6학년 1반")
      sign_in create(:user, :admin)

      get edit_admin_election_election_contest_election_candidate_path(election, contest, candidate)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보 수정")
      expect(response.body).to include("김후보")
      expect(response.body).to include("6학년 1반")
    end

    it "shows the current photo preview to admins" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "김후보")
      candidate.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")
      sign_in create(:user, :admin)

      get edit_admin_election_election_contest_election_candidate_path(election, contest, candidate)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("김후보 후보 사진")
      expect(response.body).to include("현재 사진 삭제")
    end

    it "does not show a candidate through another contest" do
      election = create(:election)
      first_contest = create(:election_contest, election: election, position: 1)
      second_contest = create(:election_contest, election: election, position: 2)
      candidate = create(:election_candidate, election_contest: first_contest)
      sign_in create(:user, :admin)

      get edit_admin_election_election_contest_election_candidate_path(election, second_contest, candidate)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/elections/:election_id/contests/:election_contest_id/candidates/:id" do
    it "updates a candidate for admins" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "김후보", affiliation_label: "6학년 1반")
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 2,
          name: "이후보",
          affiliation_label: "6학년 2반"
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(candidate.reload).to have_attributes(number: 2, name: "이후보", affiliation_label: "6학년 2반")
    end

    it "replaces a candidate photo for a draft election" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1)
      candidate.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: candidate.name,
          affiliation_label: candidate.affiliation_label,
          photo: uploaded_photo(filename: "new.png", content_type: "image/png")
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(candidate.reload.photo).to be_attached
      expect(candidate.photo.filename.to_s).to eq("new.png")
      expect(candidate.photo.content_type).to eq("image/png")
    end

    it "removes a candidate photo for a draft election" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1)
      candidate.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: candidate.name,
          affiliation_label: candidate.affiliation_label,
          remove_photo: "1"
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(candidate.reload.photo).not_to be_attached
    end

    it "keeps the new photo when photo upload and remove photo are both requested" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1)
      candidate.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: candidate.name,
          affiliation_label: candidate.affiliation_label,
          remove_photo: "1",
          photo: uploaded_photo(filename: "new.webp", content_type: "image/webp")
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(candidate.reload.photo).to be_attached
      expect(candidate.photo.filename.to_s).to eq("new.webp")
    end

    it "shows validation errors without changing a candidate to a duplicate number in the same contest" do
      election, contest = create_election_with_contest
      create(:election_candidate, election_contest: contest, number: 1)
      candidate = create(:election_candidate, election_contest: contest, number: 2, name: "기존 후보", affiliation_label: "6학년 2반")
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: "중복 수정 후보",
          affiliation_label: "6학년 3반"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("후보를 수정할 수 없습니다.")
      expect(response.body).to include("중복 수정 후보")
      expect(response.body).to include("6학년 3반")
      expect(candidate.reload).to have_attributes(number: 2, name: "기존 후보", affiliation_label: "6학년 2반")
    end

    it "does not update candidates after the election starts" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "김후보", affiliation_label: "6학년 1반")
      election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 2,
          name: "수정 차단",
          affiliation_label: "6학년 2반"
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
      expect(candidate.reload).to have_attributes(number: 1, name: "김후보", affiliation_label: "6학년 1반")
    end

    it "does not update a candidate photo after the election starts" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1)
      candidate.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: candidate.name,
          photo: uploaded_photo(filename: "new.jpg", content_type: "image/jpeg")
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
      expect(candidate.reload.photo.filename.to_s).to eq("old.jpg")
    end

    it "does not update a candidate photo after the election is closed" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest, number: 1)
      candidate.photo.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
      election.update!(status: :closed)
      sign_in create(:user, :admin)

      patch admin_election_election_contest_election_candidate_path(election, contest, candidate), params: {
        election_candidate: {
          number: 1,
          name: candidate.name,
          remove_photo: "1"
        }
      }

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
      expect(candidate.reload.photo).to be_attached
      expect(candidate.photo.filename.to_s).to eq("old.jpg")
    end
  end

  describe "DELETE /admin/elections/:election_id/contests/:election_contest_id/candidates/:id" do
    it "destroys a candidate for admins" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_contest_election_candidate_path(election, contest, candidate)
      end.to change(ElectionCandidate, :count).by(-1)

      expect(response).to redirect_to(admin_election_path(election))
    end

    it "does not allow teachers to destroy candidates" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest)
      sign_in create(:user)

      expect do
        delete admin_election_election_contest_election_candidate_path(election, contest, candidate)
      end.not_to change(ElectionCandidate, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "does not destroy a candidate through another contest" do
      election = create(:election)
      first_contest = create(:election_contest, election: election, position: 1)
      second_contest = create(:election_contest, election: election, position: 2)
      candidate = create(:election_candidate, election_contest: first_contest)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_contest_election_candidate_path(election, second_contest, candidate)
      end.not_to change(ElectionCandidate, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "does not destroy candidates after the election starts" do
      election, contest = create_election_with_contest
      candidate = create(:election_candidate, election_contest: contest)
      election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_contest_election_candidate_path(election, contest, candidate)
      end.not_to change(ElectionCandidate, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 후보자를 변경할 수 없습니다.")
    end
  end

  def create_election_with_contest
    election = create(:election)
    contest = create(:election_contest, election: election, title: "회장", position: 1)

    [ election, contest ]
  end

  def uploaded_photo(filename:, content_type:)
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.binmode
    file.write("photo")
    file.rewind

    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end
end
