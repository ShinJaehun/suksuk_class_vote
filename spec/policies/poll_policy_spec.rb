require "rails_helper"

RSpec.describe PollPolicy do
  describe "scope" do
    it "includes only the admin's own polls for admins" do
      admin = create(:user, :admin)
      own_poll = create(:poll, user: admin)
      other_poll = create(:poll)

      scope = described_class::Scope.new(admin, Poll).resolve

      expect(scope).to include(own_poll)
      expect(scope).not_to include(other_poll)
    end

    it "includes only owned polls for teachers" do
      teacher = create(:user)
      owned_election = create(:poll, user: teacher)
      other_election = create(:poll)

      scope = described_class::Scope.new(teacher, Poll).resolve

      expect(scope).to include(owned_election)
      expect(scope).not_to include(other_election)
    end

    it "is empty for guests" do
      create(:poll)

      scope = described_class::Scope.new(nil, Poll).resolve

      expect(scope).to be_empty
    end
  end

  describe "#show?" do
    it "allows teachers to view their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)

      expect(described_class.new(teacher, poll)).to be_show
    end

    it "does not allow teachers to view another teacher's poll" do
      teacher = create(:user)
      poll = create(:poll)

      expect(described_class.new(teacher, poll)).not_to be_show
    end

    it "allows admins to view another teacher's poll" do
      admin = create(:user, :admin)
      poll = create(:poll)

      expect(described_class.new(admin, poll)).to be_show
    end
  end

  describe "#create?" do
    it "allows teachers to create polls" do
      teacher = create(:user)

      expect(described_class.new(teacher, Poll)).to be_create
    end

    it "allows admins to create polls" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, Poll)).to be_create
    end

    it "does not allow guests to create polls" do
      expect(described_class.new(nil, Poll)).not_to be_create
    end
  end

  describe "#start?" do
    it "allows admins to start another teacher's poll" do
      admin = create(:user, :admin)
      poll = create(:poll)

      expect(described_class.new(admin, poll)).to be_start
    end

    it "allows teachers to start their own poll" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)

      expect(described_class.new(teacher, poll)).to be_start
    end

    it "does not allow teachers to start another teacher's poll" do
      teacher = create(:user)
      poll = create(:poll)

      expect(described_class.new(teacher, poll)).not_to be_start
    end

    it "does not allow guests to start polls" do
      poll = create(:poll)

      expect(described_class.new(nil, poll)).not_to be_start
    end
  end

  describe "Schoolwide lifecycle permissions" do
    it "allows global admin and the same-School manager" do
      school = create(:school)
      poll = create(
        :poll,
        school: school,
        school_managed: true,
        participant_group: nil
      )
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      [create(:user, :admin), manager].each do |actor|
        policy = described_class.new(actor, poll)
        expect(policy).to be_school_start
        expect(policy).to be_school_close
      end
    end

    it "rejects a regular teacher and another School manager" do
      poll = create(
        :poll,
        school: create(:school),
        school_managed: true,
        participant_group: nil
      )
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)

      [create(:user), other_manager].each do |actor|
        policy = described_class.new(actor, poll)
        expect(policy).not_to be_school_start
        expect(policy).not_to be_school_close
      end
    end
  end

  describe "#mock_candidates?" do
    let(:school) { create(:school) }
    let(:poll) do
      create(
        :poll,
        school: school,
        school_managed: true,
        participant_group: nil
      )
    end

    it "allows only global admins" do
      same_school_manager = create(:user)
      other_school_manager = create(:user)
      create(:school_membership, :manager, school: school, user: same_school_manager)
      create(
        :school_membership,
        :manager,
        school: create(:school),
        user: other_school_manager
      )

      expect(described_class.new(create(:user, :admin), poll)).to be_mock_candidates
      expect(described_class.new(same_school_manager, poll)).not_to be_mock_candidates
      expect(described_class.new(other_school_manager, poll)).not_to be_mock_candidates
      expect(described_class.new(create(:user), poll)).not_to be_mock_candidates
      expect(described_class.new(nil, poll)).not_to be_mock_candidates
    end
  end

  describe "#open_current_participant_ballot?" do
    it "allows admins to open another teacher's current participant ballot" do
      admin = create(:user, :admin)
      poll = create(:poll)

      expect(described_class.new(admin, poll)).to be_open_current_participant_ballot
    end

    it "allows teachers to open their own current participant ballot" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)

      expect(described_class.new(teacher, poll)).to be_open_current_participant_ballot
    end

    it "does not allow teachers to open another teacher's current participant ballot" do
      teacher = create(:user)
      poll = create(:poll)

      expect(described_class.new(teacher, poll)).not_to be_open_current_participant_ballot
    end
  end

  describe "#record_next_participant_absent?" do
    it "allows admins to mark another teacher's next participant absent" do
      admin = create(:user, :admin)
      poll = create(:poll)

      expect(described_class.new(admin, poll)).to be_record_next_participant_absent
    end

    it "allows teachers to mark their own next participant absent" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)

      expect(described_class.new(teacher, poll)).to be_record_next_participant_absent
    end

    it "does not allow teachers to mark another teacher's next participant absent" do
      teacher = create(:user)
      poll = create(:poll)

      expect(described_class.new(teacher, poll)).not_to be_record_next_participant_absent
    end
  end
end
