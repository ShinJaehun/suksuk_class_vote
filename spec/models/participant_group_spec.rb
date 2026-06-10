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
    it "does not destroy while used by a draft poll" do
      draft_group = create(:participant_group, :with_participant_slot)
      create(:poll, participant_group: draft_group, status: :draft)

      expect(draft_group.destroy).to be false
    end

    it "destroys when used by in-progress or closed polls" do
      participant_group = create(:participant_group, :with_participant_slot)
      in_progress_poll = create(:poll, participant_group: participant_group, status: :in_progress, participant_group_name_snapshot: participant_group.name)
      closed_poll = create(:poll, participant_group: participant_group, status: :closed, participant_group_name_snapshot: participant_group.name)

      expect(participant_group.destroy).to be_truthy
      expect(in_progress_poll.reload.participant_group).to be_nil
      expect(closed_poll.reload.participant_group).to be_nil
    end
  end
end
