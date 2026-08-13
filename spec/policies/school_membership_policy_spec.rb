require "rails_helper"

RSpec.describe SchoolMembershipPolicy do
  let(:school) { create(:school) }
  let(:member_user) { create(:user) }
  let(:membership) { create(:school_membership, school: school, user: member_user) }

  it "allows global admin to manage membership and roles" do
    policy = described_class.new(create(:user, :admin), membership)
    expect(policy).to be_index
    expect(policy).to be_create
    expect(policy).to be_promote
    expect(policy).to be_demote
    expect(policy).to be_destroy
  end

  it "allows a same-school manager to list, add, and remove another member" do
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    policy = described_class.new(manager, membership)

    expect(policy).to be_index
    expect(policy).to be_create
    expect(policy).to be_destroy
    expect(policy).not_to be_promote
    expect(policy).not_to be_demote
  end

  it "prevents a manager from removing self" do
    manager = create(:user)
    manager_membership = create(:school_membership, :manager, school: school, user: manager)

    expect(described_class.new(manager, manager_membership)).not_to be_destroy
  end

  it "blocks membership writes for an inactive School manager" do
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    school.update!(active: false)
    policy = described_class.new(manager, membership)

    expect(policy).not_to be_index
    expect(policy).not_to be_create
    expect(policy).not_to be_destroy
  end

  it "rejects another-school manager, regular teacher, and membershipless teacher" do
    other_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_manager)
    regular_teacher = create(:user)
    create(:school_membership, school: school, user: regular_teacher)

    [other_manager, regular_teacher, create(:user)].each do |actor|
      policy = described_class.new(actor, membership)
      expect(policy).not_to be_index
      expect(policy).not_to be_create
      expect(policy).not_to be_promote
      expect(policy).not_to be_demote
      expect(policy).not_to be_destroy
    end
  end
end
