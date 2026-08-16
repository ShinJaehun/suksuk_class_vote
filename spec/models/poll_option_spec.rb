require "rails_helper"

RSpec.describe PollOption, type: :model do
  describe "factory" do
    it "builds a valid poll_option" do
      poll_option = build(:poll_option)

      expect(poll_option).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_option = build(:poll_option, poll: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll]).to be_present
    end

    it "requires a poll_contest" do
      poll_option = build(:poll_option, poll_contest: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll_contest]).to be_present
    end

    it "requires a number" do
      poll_option = build(:poll_option, number: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      poll_option = build(:poll_option, number: 0)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "requires a name" do
      poll_option = build(:poll_option, name: nil)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same poll contest" do
      poll = create(:poll)
      create(:poll_option, poll: poll, number: 1)
      poll_option = build(:poll_option, poll: poll, number: 1)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:number]).to be_present
    end

    it "allows the same number in different poll contests" do
      poll = create(:poll)
      another_poll_contest = create(:poll_contest, poll: poll)
      create(:poll_option, poll: poll, number: 1)
      poll_option = build(:poll_option, poll: poll, poll_contest: another_poll_contest, number: 1)

      expect(poll_option).to be_valid
    end

    it "allows the same number in different polls" do
      create(:poll_option, number: 1)
      poll_option = build(:poll_option, number: 1)

      expect(poll_option).to be_valid
    end

    it "requires the poll_contest to belong to the poll" do
      poll = create(:poll)
      poll_contest = create(:poll_contest)
      poll_option = build(:poll_option, poll: poll, poll_contest: poll_contest)

      expect(poll_option).not_to be_valid
      expect(poll_option.errors[:poll_contest]).to be_present
    end

    it "allows an optional JPG, PNG, or WebP photo only for a Schoolwide Election" do
      [
        [ "candidate.jpg", "image/jpeg" ],
        [ "candidate.png", "image/png" ],
        [ "candidate.webp", "image/webp" ]
      ].each do |filename, content_type|
        option = schoolwide_election_option
        option.photo.attach(io: StringIO.new("image"), filename: filename, content_type: content_type)

        expect(option).to be_valid
      end

      expect(schoolwide_election_option).to be_valid
    end

    it "rejects photos for Classroom Elections and non-Election Schoolwide Polls" do
      classroom_option = build(:poll_option)
      disallowed_options = [classroom_option] + %i[survey discussion debate].map do |kind|
        schoolwide_option(kind: kind)
      end

      disallowed_options.each do |option|
        option.photo.attach(
          io: StringIO.new("image"),
          filename: "candidate.jpg",
          content_type: "image/jpeg"
        )

        expect(option).not_to be_valid
        expect(option.errors[:photo]).to be_present
      end
    end

    it "rejects unsupported content types and photos larger than 15MB" do
      invalid_type = schoolwide_election_option
      invalid_type.photo.attach(
        io: StringIO.new("text"),
        filename: "candidate.txt",
        content_type: "text/plain"
      )
      expect(invalid_type).not_to be_valid

      at_limit = schoolwide_election_option
      at_limit.photo.attach(
        io: StringIO.new("a" * PollOption::MAX_PHOTO_SIZE),
        filename: "candidate.jpg",
        content_type: "image/jpeg"
      )
      expect(at_limit).to be_valid

      oversized = schoolwide_election_option
      oversized.photo.attach(
        io: StringIO.new("a" * (PollOption::MAX_PHOTO_SIZE + 1)),
        filename: "candidate.jpg",
        content_type: "image/jpeg"
      )
      expect(oversized).not_to be_valid
      expect(oversized.errors[:photo]).to include("must be 15MB or less")
    end

    it "defines ballot and thumbnail variants" do
      option = schoolwide_election_option
      option.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")

      expect(option.photo.variant(:ballot)).to be_present
      expect(option.photo.variant(:thumbnail)).to be_present
    end
  end

  def schoolwide_election_option
    schoolwide_option(kind: :election)
  end

  def schoolwide_option(kind:)
    poll = create(
      :poll,
      school: create(:school),
      school_managed: true,
      kind: kind
    )
    contest = create(:poll_contest, poll: poll)
    build(:poll_option, poll: poll, poll_contest: contest)
  end
end
