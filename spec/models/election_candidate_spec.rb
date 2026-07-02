require "rails_helper"

RSpec.describe ElectionCandidate, type: :model do
  describe "factory" do
    it "builds a valid election candidate" do
      candidate = build(:election_candidate)

      expect(candidate).to be_valid
    end
  end

  describe "validations" do
    it "requires an election contest" do
      candidate = build(:election_candidate, election_contest: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:election_contest]).to be_present
    end

    it "requires a number" do
      candidate = build(:election_candidate, number: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      candidate = build(:election_candidate, number: 0)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "does not allow duplicate numbers in the same contest" do
      contest = create(:election_contest)
      create(:election_candidate, election_contest: contest, number: 1)
      candidate = build(:election_candidate, election_contest: contest, number: 1)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "allows the same number in different contests" do
      create(:election_candidate, number: 1)
      candidate = build(:election_candidate, number: 1)

      expect(candidate).to be_valid
    end

    it "requires a name" do
      candidate = build(:election_candidate, name: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:name]).to be_present
    end

    it "allows a blank affiliation label" do
      candidate = build(:election_candidate, affiliation_label: nil)

      expect(candidate).to be_valid
    end

    it "allows a candidate without a photo" do
      candidate = build(:election_candidate)

      expect(candidate).to be_valid
    end

    it "allows JPG, PNG, and WebP photos" do
      [
        [ "candidate.jpg", "image/jpeg" ],
        [ "candidate.png", "image/png" ],
        [ "candidate.webp", "image/webp" ]
      ].each do |filename, content_type|
        candidate = build(:election_candidate)
        candidate.photo.attach(io: StringIO.new("image"), filename: filename, content_type: content_type)

        expect(candidate).to be_valid
      end
    end

    it "does not allow a non-image photo content type" do
      candidate = build(:election_candidate)
      candidate.photo.attach(io: StringIO.new("text"), filename: "candidate.txt", content_type: "text/plain")

      expect(candidate).not_to be_valid
      expect(candidate.errors[:photo]).to be_present
    end

    it "does not allow a photo larger than 15MB" do
      candidate = build(:election_candidate)
      candidate.photo.attach(
        io: StringIO.new("a" * (ElectionCandidate::MAX_PHOTO_SIZE + 1)),
        filename: "candidate.jpg",
        content_type: "image/jpeg"
      )

      expect(candidate).not_to be_valid
      expect(candidate.errors[:photo]).to include("must be 15MB or less")
    end
  end
end
