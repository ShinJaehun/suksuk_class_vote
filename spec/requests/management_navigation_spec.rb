require "rails_helper"

RSpec.describe "Management navigation", type: :request do
  include Devise::Test::IntegrationHelpers

  it "shows School, Classroom, and Teacher resources to global admin" do
    admin = create(:user, :admin)
    sign_in admin
    get polls_path
    page = Nokogiri::HTML(response.body)
    header = page.at_css("header")
    account_link = header.at_css('[data-testid="current-user-account-link"]')

    expect(account_link.text.squish).to eq(admin.login_id)
    expect(account_link["href"]).to eq(edit_password_change_path)
    expect(header.text).not_to include(admin.email)

    expect(response.body).to include("로그아웃", %(action="#{destroy_user_session_path}"))
    expect(response.body).to include(%(href="#{schools_path}"), %(href="#{classrooms_path}"), %(href="#{teachers_path}"))
    header_text = Nokogiri::HTML(response.body).at_css("header").text.squish
    expect(header_text).not_to include("내 투표", "내 교실")
    expect(header.text.squish).not_to include("내 투표", "내 교실")
    expect(response.body).not_to include("학교 교사", "교사 관리", "School.order")
    expect(header.css('[data-testid="navigation-divider"]').size).to eq(1)
  end

  it "shows the manager's School, Classroom, and Teacher resources" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    classroom = create(:classroom, school: school, teacher: manager)
    sign_in manager
    get polls_path
    account_link = Nokogiri::HTML(response.body).at_css('[data-testid="current-user-account-link"]')
    expect(account_link.text.squish).to eq(manager.login_id)
    expect(account_link["href"]).to eq(edit_teacher_path(manager))
    expect(Nokogiri::HTML(response.body).at_css("header").text).not_to include(manager.email)
    expect(response.body).to include("로그아웃", %(action="#{destroy_user_session_path}"))
    expect(response.body).to include(
      "내 교실",
      %(href="#{classroom_students_path(classroom)}"),
      %(href="#{schools_path}"),
      %(href="#{classrooms_path}"),
      %(href="#{teachers_path}")
    )
    expect(Nokogiri::HTML(response.body).css('[data-testid="navigation-divider"]').size).to eq(2)
  end

  it "shows only the teacher's active Classroom to a regular teacher" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    sign_in teacher
    get polls_path
    account_link = Nokogiri::HTML(response.body).at_css('[data-testid="current-user-account-link"]')
    expect(account_link.text.squish).to eq(teacher.login_id)
    expect(account_link["href"]).to eq(edit_teacher_path(teacher))
    expect(Nokogiri::HTML(response.body).at_css("header").text).not_to include(teacher.email)
    expect(response.body).to include("로그아웃", %(action="#{destroy_user_session_path}"))
    expect(response.body).to include("내 교실", %(href="#{classroom_students_path(classroom)}"))
    expect(response.body).not_to include(%(href="#{schools_path}"), %(href="#{classrooms_path}"), "선생님")
    expect(Nokogiri::HTML(response.body).css('[data-testid="navigation-divider"]')).to be_empty
  end
end
