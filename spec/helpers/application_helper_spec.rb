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

    it "assigns a unique deterministic deck for the first 30 candidates and reuses it from the 31st" do
      poll = create(:poll, school: create(:school), school_managed: true)
      contest = create(:poll_contest, poll: poll)
      options = 31.times.map do |index|
        create(:poll_option, poll: poll, poll_contest: contest, number: index + 1)
      end

      paths = options.map { |option| helper.poll_option_photo_source(option, variant: :thumbnail) }

      expect(paths.first(30).uniq.size).to eq(30)
      expect(paths[30]).to eq(paths[0])
      expect(paths).to all(match(%r{\Aavatars/(boy|girl)(0[1-9]|1[0-5])\.png\z}))
    end

    it "keeps the same source fallback when mutable definition fields change" do
      option = create(:poll_option, number: 7)
      option.poll.update!(school_managed: true)
      original = helper.poll_option_photo_source(option, variant: :thumbnail)

      option.update!(number: 8, name: "변경한 후보")
      option.poll_contest.update!(position: option.poll_contest.position + 1, title: "변경한 선거")

      expect(helper.poll_option_photo_source(option, variant: :thumbnail)).to eq(original)
    end

    it "matches cloned Test Poll candidates to source occurrences" do
      school = create(:school)
      source_poll = create(:poll, school: school, school_managed: true)
      source_contest = create(:poll_contest, poll: source_poll, title: "회장 선거", position: 1)
      source_options = 2.times.map do |index|
        create(
          :poll_option,
          poll: source_poll,
          poll_contest: source_contest,
          number: index + 1,
          name: "김후보"
        )
      end
      test_poll = create(
        :poll,
        school: school,
        school_managed: true,
        test_source_poll: source_poll
      )
      test_contest = create(:poll_contest, poll: test_poll, title: source_contest.title, position: 2)
      test_options = 2.times.map do |index|
        create(
          :poll_option,
          poll: test_poll,
          poll_contest: test_contest,
          number: index + 9,
          name: source_options.first.name
        )
      end

      expect(test_options.map { |option| helper.poll_option_photo_source(option, variant: :thumbnail) }).to eq(
        source_options.map { |option| helper.poll_option_photo_source(option, variant: :thumbnail) }
      )
    end
  end
end
