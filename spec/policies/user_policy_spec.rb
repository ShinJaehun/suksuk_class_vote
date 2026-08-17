require "rails_helper"

RSpec.describe UserPolicy do
  it "keeps same-School teachers readable but not manageable for an inactive School manager" do
    school = create(:school, active: false)
    manager = create(:user)
    teacher = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    create(:school_membership, school: school, user: teacher)

    expect(described_class.new(manager, User)).to be_index
    expect(described_class::Scope.new(manager, User).resolve).to contain_exactly(manager, teacher)
    expect(described_class.new(manager, teacher)).not_to be_update
    expect(described_class.new(manager, teacher)).not_to be_deactivate
    expect(described_class.new(manager, teacher)).not_to be_issue_temporary_password
    expect(described_class.new(create(:user, :admin), teacher)).to be_update
  end

  it "does not allow teachers to update their own profile" do
    teacher = create(:user)

    expect(described_class.new(teacher, teacher)).not_to be_update
  end
end
