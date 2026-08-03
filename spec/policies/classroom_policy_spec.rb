require "rails_helper"

RSpec.describe ClassroomPolicy do
  let(:school) { create(:school) }
  let(:teacher) { create(:user) }
  let!(:membership) { create(:school_membership, school: school, user: teacher) }
  let!(:classroom) { create(:classroom, school: school, teacher: teacher) }
  let!(:other_classroom) { create(:classroom, school: create(:school), teacher: nil) }

  it "scopes admin, manager, teacher, and membershipless users" do
    admin = create(:user, :admin)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)

    expect(described_class::Scope.new(admin, Classroom).resolve).to contain_exactly(classroom, other_classroom)
    expect(described_class::Scope.new(manager, Classroom).resolve).to contain_exactly(classroom)
    expect(described_class::Scope.new(teacher, Classroom).resolve).to contain_exactly(classroom)
    expect(described_class::Scope.new(create(:user), Classroom).resolve).to be_empty
  end

  it "allows creation only for admin and manager" do
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)

    expect(described_class.new(create(:user, :admin), Classroom.new)).to be_create
    expect(described_class.new(manager, Classroom.new)).to be_create
    expect(described_class.new(teacher, Classroom.new)).not_to be_create
  end

  it "allows admin, same-school manager, and the Classroom teacher to manage it" do
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)

    [create(:user, :admin), manager, teacher].each do |actor|
      expect(described_class.new(actor, classroom)).to be_update
      expect(described_class.new(actor, classroom)).to be_manage_students
    end

    expect(described_class.new(create(:user), classroom)).not_to be_update
  end
end
