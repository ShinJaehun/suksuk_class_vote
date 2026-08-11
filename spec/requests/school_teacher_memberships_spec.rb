require "rails_helper"

RSpec.describe "School teacher memberships", type: :request do
  include Devise::Test::IntegrationHelpers

  def add_teacher(school, role: :member, name: "선생님")
    teacher = create(:user, name: name)
    membership = create(:school_membership, school: school, user: teacher, role: role)
    [teacher.reload, membership]
  end

  it "shows only the selected School memberships, roles, and Classroom links to admin" do
    school = create(:school, name: "아라초")
    teacher, teacher_membership = add_teacher(school, name: "김교사")
    manager, manager_membership = add_teacher(school, role: :manager, name: "박대표")
    classroom = create(:classroom, school: school, teacher: teacher)
    other_school = create(:school)
    other_teacher, = add_teacher(other_school, name: "타학교교사")
    sign_in create(:user, :admin)

    get school_teacher_memberships_path(school)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("선생님 관리", teacher.name, manager.name, "일반 선생님", "대표 선생님")
    expect(response.body).to include(
      promote_school_teacher_membership_path(school, teacher_membership),
      demote_school_teacher_membership_path(school, manager_membership),
      "대표 선생님 지정",
      "대표 선생님 지정 해제"
    )
    expect(response.body).not_to include("일반 선생님으로 변경")
    expect(response.body).to include(classroom.formatted_class_label, edit_classroom_path(classroom))
    expect(response.body).not_to include(other_teacher.name)
  end

  it "lets admin add an unassigned teacher as a regular member" do
    school = create(:school)
    teacher = create(:user)
    sign_in create(:user, :admin)

    expect do
      post school_teacher_memberships_path(school), params: { school_membership: { user_id: teacher.id, role: :manager } }
    end.to change(SchoolMembership, :count).by(1)

    expect(teacher.reload.school_membership).to have_attributes(school: school, role: "member")
    expect(response).to redirect_to(school_teacher_memberships_path(school))
  end

  it "lets a manager add only to their own School and cannot forge manager role" do
    school = create(:school)
    manager, = add_teacher(school, role: :manager)
    candidate = create(:user)
    sign_in manager

    post school_teacher_memberships_path(school), params: { school_membership: { user_id: candidate.id, role: :manager } }
    expect(candidate.reload.school_membership).to have_attributes(school: school, role: "member")

    other_school = create(:school)
    second_candidate = create(:user)
    expect do
      post school_teacher_memberships_path(other_school), params: { school_membership: { user_id: second_candidate.id } }
    end.not_to change(SchoolMembership, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects admins, assigned teachers, and unknown candidates" do
    school = create(:school)
    assigned_teacher, = add_teacher(create(:school))
    sign_in create(:user, :admin)

    [create(:user, :admin).id, assigned_teacher.id, -1].each do |user_id|
      expect do
        post school_teacher_memberships_path(school), params: { school_membership: { user_id: user_id } }
      end.not_to change(SchoolMembership, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "lets only admin assign, replace, repeat, and clear the single manager" do
    school = create(:school)
    _teacher, first_membership = add_teacher(school, name: "기존 대표")
    _replacement, second_membership = add_teacher(school, name: "새 대표")
    admin = create(:user, :admin)
    sign_in admin

    patch promote_school_teacher_membership_path(school, first_membership)
    expect(first_membership.reload).to be_manager
    expect(flash[:notice]).to eq("대표 선생님으로 지정했습니다.")

    patch promote_school_teacher_membership_path(school, second_membership)
    expect(first_membership.reload).to be_member
    expect(second_membership.reload).to be_manager
    expect(school.school_memberships.manager.count).to eq(1)
    expect(flash[:notice]).to eq("대표 선생님을 변경했습니다.")

    patch promote_school_teacher_membership_path(school, second_membership)
    expect(school.school_memberships.manager.sole).to eq(second_membership)

    patch demote_school_teacher_membership_path(school, second_membership)
    expect(second_membership.reload).to be_member
    expect(school.school_memberships.manager).to be_empty
    expect(flash[:notice]).to eq("대표 선생님 지정을 해제했습니다.")

    patch promote_school_teacher_membership_path(school, second_membership)
    manager = second_membership.user.reload
    sign_out admin
    sign_in manager
    patch promote_school_teacher_membership_path(school, first_membership)
    expect(response).to redirect_to(polls_path)
    patch demote_school_teacher_membership_path(school, second_membership)
    expect(response).to redirect_to(polls_path)
    expect(first_membership.reload).to be_member
    expect(second_membership.reload).to be_manager
  end

  it "rolls back both roles when replacing the manager fails" do
    school = create(:school)
    _manager, manager_membership = add_teacher(school, role: :manager, name: "기존 대표")
    _teacher, target_membership = add_teacher(school, name: "변경 대상")
    allow_any_instance_of(SchoolMembership).to receive(:update!).and_wrap_original do |method, *args|
      if method.receiver.id == target_membership.id
        raise ActiveRecord::RecordInvalid.new(method.receiver)
      end

      method.call(*args)
    end
    sign_in create(:user, :admin)

    patch promote_school_teacher_membership_path(school, target_membership)

    expect(response).to redirect_to(school_path(school))
    expect(flash[:alert]).to eq("대표 선생님을 변경할 수 없습니다.")
    expect(manager_membership.reload).to be_manager
    expect(target_membership.reload).to be_member
    expect(school.school_memberships.manager.count).to eq(1)
  end

  it "removes only the membership and blocks removal while a Classroom is assigned" do
    school = create(:school)
    teacher, membership = add_teacher(school)
    classroom = create(:classroom, school: school, teacher: teacher)
    admin = create(:user, :admin)
    sign_in admin

    expect do
      delete school_teacher_membership_path(school, membership)
    end.not_to change(SchoolMembership, :count)
    expect(flash[:alert]).to include("담당 교실을 먼저 해제")
    expect(classroom.reload.teacher).to eq(teacher)

    classroom.update!(teacher: nil)
    expect do
      delete school_teacher_membership_path(school, membership)
    end.to change(SchoolMembership, :count).by(-1).and change(User, :count).by(0)
  end

  it "lets a same-school manager remove an unassigned regular membership" do
    school = create(:school)
    manager, = add_teacher(school, role: :manager)
    teacher, membership = add_teacher(school, name: "해제 대상")
    sign_in manager

    expect do
      delete school_teacher_membership_path(school, membership)
    end.to change(SchoolMembership, :count).by(-1).and change(User, :count).by(0)
    expect(teacher.reload).to be_persisted
  end

  it "prevents a manager from removing self" do
    school = create(:school)
    manager, manager_membership = add_teacher(school, role: :manager)
    sign_in manager

    expect { delete school_teacher_membership_path(school, manager_membership) }.not_to change(SchoolMembership, :count)
    expect(response).to redirect_to(polls_path)
  end

  it "shows the replaced manager roles in membership management" do
    school = create(:school)
    old_manager, old_membership = add_teacher(school, role: :manager, name: "기존 대표")
    new_manager, new_membership = add_teacher(school, name: "새 대표")
    sign_in create(:user, :admin)

    patch promote_school_teacher_membership_path(school, new_membership)
    get school_teacher_memberships_path(school)

    page = Nokogiri::HTML(response.body)
    new_manager_row = page.css("li").find { |row| row.text.include?(new_manager.name) }
    old_manager_row = page.css("li").find { |row| row.text.include?(old_manager.name) }

    expect(new_manager_row).to be_present
    expect(old_manager_row).to be_present
    expect(
      new_manager_row.at_css(
        %(form[action="#{demote_school_teacher_membership_path(school, new_membership)}"])
      )
    ).to be_present
    expect(
      old_manager_row.at_css(
        %(form[action="#{promote_school_teacher_membership_path(school, old_membership)}"])
      )
    ).to be_present
    expect(new_manager_row.text).to include("대표 선생님")
    expect(old_manager_row.text).to include("일반 선생님")
  end

  it "returns 404 when deleting a membership from another parent School" do
    school = create(:school)
    _teacher, membership = add_teacher(create(:school))
    sign_in create(:user, :admin)

    delete school_teacher_membership_path(school, membership)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload).to be_persisted
  end

  it "returns 404 when promoting a membership from another parent School" do
    school = create(:school)
    _teacher, membership = add_teacher(create(:school))
    sign_in create(:user, :admin)

    patch promote_school_teacher_membership_path(school, membership)

    expect(response).to have_http_status(:not_found)
    expect(membership.reload).to be_member
  end

  it "rejects regular and membershipless teachers" do
    school = create(:school)
    teacher, membership = add_teacher(school)

    sign_in teacher
    get school_teacher_memberships_path(school)
    expect(response).to redirect_to(polls_path)

    sign_out teacher
    sign_in create(:user)
    get school_teacher_memberships_path(school)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload).to be_persisted
  end

  it "feeds the new member into same-school Classroom settings and the teacher roster flow" do
    school = create(:school)
    teacher = create(:user, name: "새담임")
    classroom = create(:classroom, school: school, teacher: nil)
    other_classroom = create(:classroom, school: create(:school), teacher: nil)
    admin = create(:user, :admin)
    sign_in admin
    post school_teacher_memberships_path(school), params: { school_membership: { user_id: teacher.id } }

    get edit_classroom_path(classroom)
    expect(response.body).to include(teacher.name)
    get edit_classroom_path(other_classroom)
    expect(response.body).not_to include(teacher.name)

    patch classroom_path(classroom), params: { classroom: { school_year: classroom.school_year, grade: classroom.grade, class_label: classroom.class_label, teacher_id: teacher.id, active: true } }
    sign_out admin
    sign_in teacher.reload
    get classrooms_path
    expect(response).to redirect_to(classroom_students_path(classroom))
  end
end
