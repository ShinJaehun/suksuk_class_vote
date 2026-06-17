FactoryBot.define do
  factory :school_election do
    association :user, :admin
    title { "2026학년도 전교학생회 선거" }
    status { :draft }
  end
end
