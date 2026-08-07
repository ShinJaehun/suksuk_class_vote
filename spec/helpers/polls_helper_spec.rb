require "rails_helper"

RSpec.describe PollsHelper, type: :helper do
  def school_poll(test_source_poll: nil)
    school = test_source_poll&.school || create(:school)
    create(:poll, school: school, school_managed: true, participant_group: nil,
                  test_source_poll: test_source_poll)
  end

  it "adds test and replacement badges in the common order" do
    source = school_poll
    test_poll = school_poll(test_source_poll: source)
    classroom = create(:classroom, :with_teacher, school: source.school)
    source_session = create(:poll_session, poll: test_poll, classroom: classroom,
                                           operator: classroom.teacher, status: :stopped,
                                           started_at: 1.hour.ago, stopped_at: Time.current)
    test_poll.update!(status: :in_progress, started_at: 1.hour.ago)
    replacement = create(:poll_session, poll: test_poll, classroom: classroom,
                                        operator: classroom.teacher, replacement_of: source_session)

    test_badges = Nokogiri::HTML.fragment(
      helper.poll_badges(poll: test_poll, status_record: replacement)
    ).text.squish
    source_badges = Nokogiri::HTML.fragment(
      helper.poll_badges(poll: source, status_record: source)
    ).text.squish

    expect(test_badges)
      .to eq("전교 테스트 재투표 선거 준비")
    expect(source_badges).to eq("전교 선거 준비")
  end

  it "adds a display-only revote suffix without changing Poll title" do
    poll = school_poll
    classroom = create(:classroom, :with_teacher, school: poll.school)
    original = create(:poll_session, poll: poll, classroom: classroom,
                                     operator: classroom.teacher, status: :stopped,
                                     started_at: 1.hour.ago, stopped_at: Time.current)
    poll.update!(status: :in_progress, started_at: 1.hour.ago)
    replacement = create(:poll_session, poll: poll, classroom: classroom,
                                        operator: classroom.teacher, replacement_of: original)

    expect(helper.poll_session_display_title(original)).to eq(poll.title)
    expect(helper.poll_session_display_title(replacement)).to eq("#{poll.title} (재투표)")
    expect(poll.reload.title).not_to end_with("(재투표)")
  end
end
