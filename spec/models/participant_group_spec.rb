require "rails_helper"

RSpec.describe ParticipantGroup, type: :model do
  describe "factory" do
    it "builds a valid participant group" do
      participant_group = build(:participant_group)

      expect(participant_group).to be_valid
    end
  end

  describe "validations" do
    it "requires a name" do
      participant_group = build(:participant_group, name: nil)

      expect(participant_group).not_to be_valid
      expect(participant_group.errors[:name]).to be_present
    end

    it "requires a user" do
      participant_group = build(:participant_group, user: nil)

      expect(participant_group).not_to be_valid
      expect(participant_group.errors[:user]).to be_present
    end
  end

  describe "destroy guard" do
    it "does not destroy while used by a draft or in-progress election" do
      draft_group = create(:participant_group, :with_participant_slot)
      in_progress_group = create(:participant_group, :with_participant_slot)
      create(:poll, participant_group: draft_group, status: :draft)
      create(:poll, participant_group: in_progress_group, status: :in_progress)

      expect(draft_group.destroy).to be false
      expect(in_progress_group.destroy).to be false
    end

    it "destroys when used only by closed elections" do
      participant_group = create(:participant_group, :with_participant_slot)
      election = create(:poll, participant_group: participant_group, status: :closed, participant_group_name_snapshot: participant_group.name)

      expect(participant_group.destroy).to be_truthy
      expect(election.reload.participant_group).to be_nil
    end
  end
end
