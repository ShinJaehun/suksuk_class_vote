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

    it "broadcasts without rendering classroom sessions in the legacy assignment partial" do
      election = create(:election)
      classroom = create(:classroom)
      create(
        :election_session,
        election: election,
        teacher: create(:user),
        participant_group: nil,
        classroom: classroom
      )

      expect { described_class.new(election: election).call }.not_to raise_error

      broadcasts = admin_overview_broadcasts_for(election)
      expect(broadcasts.size).to eq(3)
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_summary))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_status_report))
      expect(broadcasts.join).to include(ActionView::RecordIdentifier.dom_id(election, :admin_sessions))
    end
  end

  def admin_overview_broadcasts_for(election)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election, :admin_overview ]))
  end
end
