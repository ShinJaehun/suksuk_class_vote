FactoryBot.define do
  factory :poll_session do
    classroom { create(:classroom, :with_teacher) }
    poll { create(:poll, school: classroom.school, participant_group: nil) }
    operator { classroom.teacher }
    status { :draft }
    classroom_name_snapshot do
      "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
    end
    operator_name_snapshot { operator&.name.presence || operator&.email }  end
end
