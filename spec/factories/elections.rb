FactoryBot.define do
  factory :election do
    association :user, :admin
    association :school
    title { "2026학년도 전교학생회 선거" }
    kind { :school_council }
    status { :draft }
  end
end
