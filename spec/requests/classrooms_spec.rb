require "rails_helper"

RSpec.describe "Classrooms", type: :request do
  include Devise::Test::IntegrationHelpers

  def teacher_for(school, name: "담임")
    user = create(:user, name: name)
    create(:school_membership, school: school, user: user)
    user.reload
  end

  def classroom_params(school:, teacher:, overrides: {})
    { classroom: { school_id: school.id, school_year: 2026, grade: 4, class_label: "1", teacher_id: teacher.id, active: true }.merge(overrides) }
  end

  it "shows all Classrooms and the school filter to admin" do
    first_school = create(:school, name: "가학교")
    second_school = create(:school, name: "나학교")
    first = create(:classroom, school: first_school, teacher: teacher_for(first_school))
    second = create(:classroom, school: second_school, teacher: teacher_for(second_school))
    create(:student, classroom: first)
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: first_school.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(first.formatted_class_label, "학교 필터", "교실 생성", "학생 1/1명")
    expect(response.body).not_to include(second.formatted_class_label)
    document = Nokogiri::HTML(response.body)
    selector = document.at_css("form[data-controller='autosubmit'][data-turbo-frame='classroom_management'][data-action='change->autosubmit#submit'] select[name='school_id']")
    expect(selector.css("option").map(&:text)).to include("전체 학교", first_school.name, second_school.name)
    expect(document.at_css("turbo-frame#classroom_management")).to be_present
    expect(response.body).not_to include(">적용<")

    get classrooms_path
    expect(response.body).to include(first.formatted_class_label, second.formatted_class_label)
  end

  it "scopes managers and teachers and redirects a teacher with one Classroom" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    own_teacher = teacher_for(school)
    own = create(:classroom, school: school, teacher: own_teacher)
    other_school_classroom = create(:classroom, school: create(:school), teacher: nil)

    sign_in manager
    get classrooms_path
    expect(response.body).to include(own.name, "교실 생성")
    expect(response.body).not_to include(other_school_classroom.name, "학교 필터")

    sign_out manager
    sign_in own_teacher
    get classrooms_path
    expect(response).to redirect_to(classroom_students_path(own))
  end

  it "shows an empty state to a membershipless teacher" do
    sign_in create(:user)
    get classrooms_path
    expect(response.body).to include("배정된 교실이 없습니다.")
    expect(response.body).not_to include("교실 생성")
  end

  it "lets admin and manager create only with a teacher from the selected school" do
    school = create(:school)
    teacher = teacher_for(school)
    admin = create(:user, :admin)
    sign_in admin

    expect { post classrooms_path, params: classroom_params(school: school, teacher: teacher) }.to change(Classroom, :count).by(1)
    expect(response).to redirect_to(classroom_students_path(Classroom.order(:created_at).last))

    other_school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    other_teacher = teacher_for(other_school)
    sign_out admin
    sign_in manager

    expect do
      post classrooms_path, params: classroom_params(school: other_school, teacher: other_teacher, overrides: { class_label: "2" })
    end.not_to change(Classroom, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "prefills the School when creating from School detail" do
    school = create(:school)
    sign_in create(:user, :admin)

    get new_classroom_path(school_id: school.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    selected_option = document.at_css('select[name="classroom[school_id]"] option[selected]')

    expect(selected_option&.[]("value")).to eq(school.id.to_s)
  end

  it "prevents a regular teacher from changing protected Classroom fields" do
    school = create(:school)
    teacher = teacher_for(school)
    classroom = create(:classroom, school: school, teacher: teacher)
    replacement = teacher_for(school, name: "다른 담임")
    sign_in teacher

    patch classroom_path(classroom), params: classroom_params(
      school: create(:school),
      teacher: replacement,
      overrides: { school_year: 2027, grade: 5, class_label: "생활교육실", active: false }
    )

    expect(response).to redirect_to(edit_classroom_path(classroom))
    expect(classroom.reload).to have_attributes(school_year: 2027, grade: 5, class_label: "생활교육실", school: school, teacher: teacher, active: true)
  end

  it "denies Classroom creation to a regular teacher" do
    school = create(:school)
    teacher = teacher_for(school)
    sign_in teacher
    expect { post classrooms_path, params: classroom_params(school: school, teacher: teacher) }.not_to change(Classroom, :count)
    expect(response).to redirect_to(polls_path)
  end
end
