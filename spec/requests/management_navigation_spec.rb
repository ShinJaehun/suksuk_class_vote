require "rails_helper"

RSpec.describe "Management navigation", type: :request do
  include Devise::Test::IntegrationHelpers

  it "shows School, Classroom, and Teacher resources to global admin" do
    sign_in create(:user, :admin)
    get polls_path
    expect(response.body).to include(%(href="#{schools_path}"), %(href="#{classrooms_path}"), %(href="#{teachers_path}"))
    expect(response.body).not_to include("학교 교사", "교사 관리", "School.order")
  end

  it "shows the manager's School, Classroom, and Teacher resources" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    sign_in manager
    get polls_path
    expect(response.body).to include(%(href="#{schools_path}"), %(href="#{classrooms_path}"), %(href="#{teachers_path}"))
  end

  it "shows only Classroom management to a regular teacher" do
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    sign_in teacher
    get polls_path
    expect(response.body).to include(%(href="#{classrooms_path}"))
    expect(response.body).not_to include(%(href="#{schools_path}"), "선생님")
  end
end
