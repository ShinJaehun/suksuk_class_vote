require "rails_helper"

RSpec.describe SchoolPolicy do
  let(:school) { create(:school) }

  it "allows global admin full School management" do
    admin = create(:user, :admin)
    policy = described_class.new(admin, school)
    expect(policy).to be_index
    expect(policy).to be_show
    expect(policy).to be_create
    expect(policy).to be_update
    expect(described_class::Scope.new(admin, School).resolve).to include(school)
  end

  it "allows a manager to see only their School" do
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    policy = described_class.new(manager, school)
    expect(policy).to be_index
    expect(policy).to be_show
    expect(policy).not_to be_create
    expect(policy).not_to be_update
    expect(described_class::Scope.new(manager, School).resolve).to contain_exactly(school)
  end

  it "rejects regular and membershipless teachers" do
    regular = create(:user)
    create(:school_membership, school: school, user: regular)
    [regular, create(:user)].each do |actor|
      expect(described_class.new(actor, school)).not_to be_index
      expect(described_class.new(actor, school)).not_to be_show
      expect(described_class::Scope.new(actor, School).resolve).to be_empty
    end
  end
end
