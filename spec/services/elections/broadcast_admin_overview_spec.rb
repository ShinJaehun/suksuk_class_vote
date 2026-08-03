require "rails_helper"

RSpec.describe Elections::BroadcastAdminOverview do
  include ActionCable::TestHelper

  describe "#call" do
    it "broadcasts the existing admin overview for participant group sessions" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(
        :election_session,
        election: election,
        teacher: teacher,
        participant_group: participant_group
      )

      described_class.new(election: election).call

      broadcasts = admin_overview_broadcasts_for(election)
      expect(broadcasts.size).to eq(3)
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_summary))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_status_report))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_sessions))
      expect(broadcasts.join).to include(participant_group.display_name)
    end

    it "broadcasts classroom and participant group sessions together" do
      election = create(:election)
      legacy_teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: legacy_teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:election_session, election: election, teacher: legacy_teacher, participant_group: participant_group)
      classroom = create(:classroom, :with_teacher, school: election.school, grade: 5, class_number: 2)
      create(:student, classroom: classroom)
      create(
        :election_session,
        election: election,
        teacher: classroom.teacher,
        participant_group: nil,
        classroom: classroom
      )

      expect { described_class.new(election: election).call }.not_to raise_error

      broadcasts = admin_overview_broadcasts_for(election)
      expect(broadcasts.size).to eq(3)
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_summary))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_status_report))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_sessions))
      expect(broadcasts.join).to include(participant_group.display_name)
      expect(broadcasts.join).to include("#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.class_number}반")
    end
  end

  def admin_overview_broadcasts_for(election)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election, :admin_overview ]))
  end
end
