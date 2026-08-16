require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#poll_option_photo_source" do
    it "returns the requested ballot and thumbnail representation paths" do
      option = build(:poll_option)
      option.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")
      ballot = instance_double(ActiveStorage::VariantWithRecord)
      thumbnail = instance_double(ActiveStorage::VariantWithRecord)
      allow(option.photo).to receive(:variant).with(:ballot).and_return(ballot)
      allow(option.photo).to receive(:variant).with(:thumbnail).and_return(thumbnail)
      allow(helper).to receive(:rails_representation_path)
        .with(ballot, only_path: true)
        .and_return("/photo/ballot")
      allow(helper).to receive(:rails_representation_path)
        .with(thumbnail, only_path: true)
        .and_return("/photo/thumbnail")

      expect(helper.poll_option_photo_source(option, variant: :ballot)).to eq("/photo/ballot")
      expect(helper.poll_option_photo_source(option, variant: :thumbnail)).to eq("/photo/thumbnail")
    end

    it "returns a deterministic boy or girl avatar in the 01 through 15 range" do
      option = create(:poll_option)

      first = helper.poll_option_photo_source(option, variant: :thumbnail)
      second = helper.poll_option_photo_source(option, variant: :ballot)

      expect(first).to eq(second)
      expect(first).to match(%r{\Aavatars/(boy|girl)(0[1-9]|1[0-5])\.png\z})
    end

    it "uses definition positions so cloned options keep the same fallback avatar" do
      option = create(:poll_option, number: 7)
      cloned_poll = create(:poll, school: create(:school), school_managed: true)
      cloned_contest = create(:poll_contest, poll: cloned_poll, position: option.poll_contest.position)
      cloned_option = create(:poll_option, poll: cloned_poll, poll_contest: cloned_contest, number: option.number)
      avatar_index = ((option.poll_contest.position * 7) + (option.number * 11)) % 30
      prefix = avatar_index.even? ? "boy" : "girl"
      number = ((avatar_index / 2) % 15) + 1

      expect(helper.poll_option_photo_source(option, variant: :thumbnail)).to eq(
        "avatars/#{prefix}#{number.to_s.rjust(2, "0")}.png"
      )
      expect(helper.poll_option_photo_source(cloned_option, variant: :thumbnail)).to eq(
        helper.poll_option_photo_source(option, variant: :thumbnail)
      )
    end
  end
end
