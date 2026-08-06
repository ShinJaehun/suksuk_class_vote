require "rails_helper"

RSpec.describe "Schools", type: :request do
  include Devise::Test::IntegrationHelpers

  def add_teacher(school, role: :member, name: "선생님")
    teacher = create(:user, name: name)
    create(:school_membership, school: school, user: teacher, role: role)
    teacher.reload
  end

  it "shows every School and resource summaries to global admin" do
    school = create(:school, name: "아라초")
    manager = add_teacher(school, role: :manager, name: "대표교사")
    classroom = create(:classroom, school: school, teacher: manager)
    create(:student, classroom: classroom)
    other_school = create(:school, name: "다른초")
    sign_in create(:user, :admin)

    get schools_path
    expect(response.body).to include(school.name, other_school.name, "학교 생성", "교실 1개", "소속 선생님 1명", manager.name)

    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("학교 기본 정보", "대표 선생님", "교실", "선생님")
    expect(response.body).to include(classroom.formatted_class_label, "학생 관리", "새 교실 만들기", "선생님 추가")
  end

  it "lets only global admin create and update a School" do
    admin = create(:user, :admin)
    sign_in admin
    expect { post schools_path, params: { school: { name: "새학교" } } }.to change(School, :count).by(1)
    school = School.find_by!(name: "새학교")
    patch school_path(school), params: { school: { name: "수정학교" } }
    expect(school.reload.name).to eq("수정학교")

    sign_out admin
    manager = add_teacher(school, role: :manager)
    sign_in manager
    expect { post schools_path, params: { school: { name: "차단학교" } } }.not_to change(School, :count)
    expect(response).to redirect_to(polls_path)
  end

  it "redirects a manager to their School and hides other Schools" do
    school = create(:school)
    manager = add_teacher(school, role: :manager)
    other_school = create(:school)
    sign_in manager

    get schools_path
    expect(response).to redirect_to(school_path(school))
    get school_path(other_school)
    expect(response).to have_http_status(:not_found)

    get school_path(school)
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제", "학교 정보 수정")
  end

  it "rejects regular and membershipless teachers" do
    school = create(:school)
    regular = add_teacher(school)

    [regular, create(:user)].each do |actor|
      sign_in actor
      get schools_path
      expect(response).to redirect_to(polls_path)
      sign_out actor
    end
  end

  it "manages representative roles only from the School detail" do
    school = create(:school)
    teacher = add_teacher(school)
    membership = teacher.school_membership
    sign_in create(:user, :admin)

    get school_path(school)
    expect(response.body).to include("대표 선생님 지정")
    patch promote_school_teacher_membership_path(school, membership)
    expect(membership.reload).to be_manager
    get school_path(school)
    expect(response.body).to include("대표 선생님 지정 해제")
  end
end
