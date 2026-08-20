require "rails_helper"

RSpec.describe Poll, type: :model do
  describe "factory" do
    it "builds a valid poll" do
      poll = build(:poll)

      expect(poll).to be_valid
    end
  end

  describe "validations" do
    it "allows abstention by default and accepts either policy value" do
      poll = Poll.new

      expect(poll.abstention_allowed).to be(true)
      expect(build(:poll, abstention_allowed: false)).to be_valid
      expect(build(:poll, abstention_allowed: nil)).to be_invalid
    end

    it "requires a title" do
      poll = build(:poll, title: nil)

      expect(poll).not_to be_valid
      expect(poll.errors[:title]).to be_present
    end

    it "requires a user" do
      poll = build(:poll, user: nil)

      expect(poll).not_to be_valid
      expect(poll.errors[:user]).to be_present
    end

    it "requires a school" do
      poll = build(:poll, school: nil)

      expect(poll).to be_invalid
      expect(poll.errors[:school]).to be_present
    end
  end

  describe "abstention policy" do
    it "can change only while the definition is editable" do
      poll = create(:poll)

      expect { poll.update!(abstention_allowed: false) }
        .to change { poll.reload.abstention_allowed }.from(true).to(false)

      classroom = create(:classroom, school: poll.school)
      operator = poll.user
      session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator,
        operator_name_snapshot: operator.name.presence || operator.login_id
      )
      create(:poll_progress, poll: poll, poll_session: session)

      expect(poll.update(abstention_allowed: true)).to be(false)
      expect(poll.errors[:abstention_allowed]).to be_present
      expect(poll.reload.abstention_allowed).to be(false)
    end
  end

  describe "advancement policy" do
    it "defaults to teacher confirmation and changes only while the definition is editable" do
      poll = create(:poll)

      expect(poll).to be_teacher_confirmed
      expect(build(:poll, advancement_mode: nil)).to be_invalid
      expect { poll.update!(advancement_mode: :automatic) }
        .to change { poll.reload.advancement_mode }.from("teacher_confirmed").to("automatic")
      classroom = create(:classroom, school: poll.school)
      operator = poll.user
      session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: operator,
        operator_name_snapshot: operator.name.presence || operator.login_id
      )
      create(:poll_progress, poll: poll, poll_session: session)

      expect(poll.update(advancement_mode: :teacher_confirmed)).to be(false)
      expect(poll.errors[:advancement_mode]).to be_present
      expect(poll.reload).to be_automatic
    end
  end

  describe "poll contests" do
    it "creates a default poll contest when a poll is created" do
      poll = create(:poll)

      expect(poll.default_poll_contest).to have_attributes(
        title: "기본",
        position: 1
      )
    end
  end

  describe "Schoolwide test Poll relationship" do
    it "tracks source and test Polls without inferring from title" do
      source = create(:poll, school: create(:school), school_managed: true)
      test_poll = create(:poll, title: "이름에 표시 없음", school: source.school,
                                school_managed: true, test_source_poll: source)

      expect(source).not_to be_test_run
      expect(test_poll).to be_test_run
      expect(test_poll.test_source_poll).to eq(source)
      expect(source.test_polls).to contain_exactly(test_poll)
    end
  end

  describe "status" do
    it "defaults to draft" do
      poll = Poll.new

      expect(poll).to be_draft
    end

    it "supports in progress, closed, and stopped statuses" do
      poll = build(:poll, status: :in_progress)

      expect(poll).to be_in_progress
      expect(Poll.statuses).to include("closed" => 20, "stopped" => 30)
    end

    it "validates Schoolwide Poll lifecycle timestamps by status" do
      started_at = 1.hour.ago
      school = create(:school)
      attributes = { school: school, school_managed: true }

      expect(build(:poll, **attributes, status: :stopped,
                                    started_at: started_at, stopped_at: Time.current)).to be_valid
      expect(build(:poll, **attributes, status: :stopped,
                                    started_at: nil, stopped_at: Time.current)).to be_invalid
      expect(build(:poll, **attributes, status: :stopped,
                                    started_at: started_at, stopped_at: nil)).to be_invalid
      expect(build(:poll, **attributes, status: :stopped, started_at: started_at,
                                    stopped_at: Time.current, closed_at: Time.current)).to be_invalid
      expect(build(:poll, **attributes, status: :stopped, started_at: started_at,
                                    stopped_at: 2.hours.ago)).to be_invalid
      expect(build(:poll, **attributes, status: :in_progress, started_at: started_at,
                                    stopped_at: Time.current)).to be_invalid
      expect(build(:poll, **attributes, status: :closed, started_at: started_at,
                                    closed_at: Time.current, stopped_at: Time.current)).to be_invalid
    end

    it "does not apply Schoolwide stopped timestamp rules to a Classroom Poll" do
      poll = build(:poll, school: create(:school), school_managed: false, status: :stopped, stopped_at: nil)

      expect(poll).to be_valid
    end

    it "allows a stopped Classroom Poll" do
      poll = build(:poll, status: :stopped)

      expect(poll).to be_valid
    end
  end

  describe "kind" do
    it "defaults to poll" do
      poll = Poll.new

      expect(poll).to be_election
    end

    it "supports discussion, debate, and survey kinds without changing existing values" do
      discussion = build(:poll, :discussion)
      debate = build(:poll, :debate)
      survey = build(:poll, kind: :survey)

      expect(discussion).to be_discussion
      expect(debate).to be_debate
      expect(survey).to be_survey
      expect(Poll.kinds).to include(
        "election" => 0,
        "discussion" => 10,
        "debate" => 20,
        "survey" => 30
      )
    end
  end

  describe "display labels" do
    it "returns poll labels" do
      poll = build(:poll)

      expect(poll.activity_label).to eq("선거")
      expect(poll.contest_label).to eq("선거 항목")
      expect(poll.choice_label).to eq("후보자")
      expect(poll.choice_list_label).to eq("후보자")
      expect(poll.choice_number_label).to eq("기호")
      expect(poll.winner_label).to eq("최다 득표 후보")
      expect(poll.vote_count_label).to eq("득표수")
    end

    it "returns discussion labels" do
      poll = build(:poll, :discussion)

      expect(poll.activity_label).to eq("토의")
      expect(poll.contest_label).to eq("토의 주제")
      expect(poll.choice_label).to eq("의견")
      expect(poll.choice_list_label).to eq("의견")
      expect(poll.choice_number_label).to eq("번호")
      expect(poll.winner_label).to eq("가장 많이 선택된 의견")
      expect(poll.vote_count_label).to eq("선택 수")
    end

    it "returns debate labels" do
      poll = build(:poll, :debate)

      expect(poll.activity_label).to eq("토론")
      expect(poll.contest_label).to eq("토론 쟁점")
      expect(poll.choice_label).to eq("입장")
      expect(poll.choice_list_label).to eq("입장")
      expect(poll.choice_number_label).to eq("번호")
      expect(poll.winner_label).to eq("가장 많이 선택된 입장")
      expect(poll.vote_count_label).to eq("선택 수")
    end

    it "returns survey labels" do
      poll = build(:poll, kind: :survey)

      expect(poll.activity_label).to eq("설문조사")
      expect(poll.contest_label).to eq("설문 문항")
      expect(poll.choice_label).to eq("선택지")
      expect(poll.choice_number_label).to eq("번호")
      expect(poll.vote_count_label).to eq("응답 수")
    end
  end

  describe "Schoolwide lifecycle timestamps" do
    let(:school_poll) do
      build(
        :poll,
        school: create(:school),
        school_managed: true
      )
    end

    it "requires consistent timestamps for in-progress and closed Schoolwide Polls" do
      school_poll.status = :in_progress
      expect(school_poll).to be_invalid

      school_poll.started_at = Time.current
      expect(school_poll).to be_valid

      school_poll.status = :closed
      expect(school_poll).to be_invalid

      school_poll.closed_at = school_poll.started_at - 1.minute
      expect(school_poll).to be_invalid

      school_poll.closed_at = school_poll.started_at + 1.minute
      expect(school_poll).to be_valid
    end

    it "stops lifecycle duration at stopped_at" do
      started_at = Time.zone.local(2026, 8, 6, 10, 0, 0)
      stopped_at = Time.zone.local(2026, 8, 6, 10, 42, 0)
      school_poll.assign_attributes(
        status: :stopped,
        started_at: started_at,
        stopped_at: stopped_at
      )

      expect(school_poll).to be_valid
      expect(
        school_poll.lifecycle_duration_minutes(
          now: Time.zone.local(2026, 8, 6, 14, 0, 0)
        )
      ).to eq(42)
    end

    it "does not apply the strict lifecycle contract to Classroom Polls" do
      poll = build(:poll, status: :in_progress, started_at: nil)

      expect(poll).to be_valid
    end
  end

  describe "destroy policy" do
    it "allows draft, stopped, and unarchived closed polls to be destroyed" do
      draft_poll = create(:poll)
      stopped_poll = create(:poll, status: :stopped)
      closed_poll = create(:poll, status: :closed)

      expect(draft_poll.destroy).to be_truthy
      expect(stopped_poll.destroy).to be_truthy
      expect(closed_poll.destroy).to be_truthy
    end

    it "blocks in progress and archived closed polls from being destroyed" do
      in_progress_poll = create(:poll, status: :in_progress)
      archived_closed_poll = create(:poll, status: :closed, archived_at: Time.current)

      expect(in_progress_poll.destroy).to be_falsey
      expect(archived_closed_poll.destroy).to be_falsey
      expect(in_progress_poll.errors[:base]).to include("진행 중이거나 보관된 투표는 삭제할 수 없습니다.")
      expect(archived_closed_poll.errors[:base]).to include("진행 중이거나 보관된 투표는 삭제할 수 없습니다.")
    end
  end
end
