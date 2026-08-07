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

      actors = [create(:user, :admin), manager]
      actors.each do |actor|
        policy = described_class.new(actor, poll)
        expect(policy).to be_school_start
        expect(policy).not_to be_school_close
        expect(policy).not_to be_school_stop
      end
      poll.update!(status: :in_progress, started_at: Time.current)
      actors.each do |actor|
        policy = described_class.new(actor, poll)
        expect(policy).to be_school_close
        expect(policy).to be_school_stop
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
        expect(policy).not_to be_school_stop
      end
    end
  end

  describe "Schoolwide test Poll permissions" do
    it "allows manager/admin creation from a draft source and keeps test runtime lifecycle available" do
      school = create(:school)
      source = create(:poll, school: school, school_managed: true, participant_group: nil)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      [manager, create(:user, :admin)].each do |actor|
        expect(described_class.new(actor, source)).to be_school_test
      end
      expect(described_class.new(create(:user), source)).not_to be_school_test

      test_poll = create(:poll, school: school, school_managed: true,
                                participant_group: nil, test_source_poll: source)
      policy = described_class.new(manager, test_poll)
      expect(policy).not_to be_school_test
      expect(policy).not_to be_school_edit
      expect(policy).not_to be_school_update
      expect(policy).to be_school_start

      test_poll.update!(status: :in_progress, started_at: Time.current)
      expect(described_class.new(manager, test_poll)).to be_school_close
      test_poll.update!(status: :closed, closed_at: Time.current, archived_at: Time.current)
      expect(described_class.new(manager, test_poll)).to be_school_results
    end

    it "keeps stopped child results readable after the source closes" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      source = create(:poll, school: school, school_managed: true, participant_group: nil,
                             status: :closed, started_at: 1.hour.ago,
                             closed_at: Time.current, archived_at: Time.current)
      test_poll = create(:poll, school: school, school_managed: true,
                                participant_group: nil, test_source_poll: source,
                                status: :stopped, started_at: 1.hour.ago,
                                stopped_at: Time.current)

      expect(described_class.new(manager, test_poll)).to be_school_show
      expect(described_class.new(manager, test_poll)).to be_school_results
      expect(described_class.new(manager, test_poll)).not_to be_school_start
      expect(described_class.new(manager, test_poll)).not_to be_reset_schoolwide
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

  describe "#reset_schoolwide?" do
    it "allows global admin and the same-School manager for a resettable Schoolwide Poll" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      expect(described_class.new(create(:user, :admin), poll)).to be_reset_schoolwide
      expect(described_class.new(manager, poll)).to be_reset_schoolwide
      expect(described_class.new(create(:user), poll)).not_to be_reset_schoolwide
      expect(described_class.new(nil, poll)).not_to be_reset_schoolwide

      poll.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current,
                   archived_at: Time.current)
      expect(described_class.new(create(:user, :admin), poll)).not_to be_reset_schoolwide
    end

    it "rejects a regular classroom Poll even for global admin" do
      expect(described_class.new(create(:user, :admin), create(:poll))).not_to be_reset_schoolwide
    end
  end

  describe "#destroy_schoolwide?" do
    it "applies manager preservation rules and allows global admin in every state" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      admin = create(:user, :admin)

      %i[draft in_progress stopped closed].each do |status|
        attributes = {
          status: status,
          started_at: (1.hour.ago unless status == :draft),
          stopped_at: (Time.current if status == :stopped),
          closed_at: (Time.current if status == :closed),
          archived_at: (Time.current if status == :closed)
        }
        source = create(:poll, school: school, school_managed: true,
                               participant_group: nil, **attributes)
        test_poll = create(:poll, school: school, school_managed: true,
                                  participant_group: nil, test_source_poll: source, **attributes)

        expect(described_class.new(manager, source).destroy_schoolwide?).to eq(status == :draft)
        expect(described_class.new(manager, test_poll).destroy_schoolwide?).to eq(status != :in_progress)
        expect(described_class.new(admin, source)).to be_destroy_schoolwide
        expect(described_class.new(admin, test_poll)).to be_destroy_schoolwide
      end

      source = create(:poll, school: school, school_managed: true, participant_group: nil)
      archived_test = create(:poll, school: school, school_managed: true,
                                    participant_group: nil, test_source_poll: source,
                                    status: :stopped, started_at: 1.hour.ago,
                                    stopped_at: Time.current, archived_at: Time.current)
      expect(described_class.new(manager, archived_test)).to be_destroy_schoolwide
    end

    it "rejects another-School manager" do
      poll = create(:poll, school: create(:school), school_managed: true, participant_group: nil)
      manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: manager)

      expect(described_class.new(manager, poll)).not_to be_destroy_schoolwide
      expect(described_class.new(manager, poll)).not_to be_reset_schoolwide
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
