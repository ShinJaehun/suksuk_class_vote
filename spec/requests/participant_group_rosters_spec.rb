require "rails_helper"

RSpec.describe "Participant group rosters", type: :request do
  include Devise::Test::IntegrationHelpers

  it "shows every student in one edit form" do
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "첫째")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "둘째")
    sign_in teacher

    get edit_participant_group_roster_path(participant_group)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("첫째")
    expect(response.body).to include("둘째")
    expect(response.body).to include("저장")
    expect(response.body).to include("취소")
    expect(response.body).to include("삭제")
    expect(response.body).to include('type="hidden"')
    expect(response.body).to include("roster[slots][0][_destroy]")
    expect(response.body).not_to include('type="checkbox"')
  end

  it "keeps the safe admin return path through edit and update" do
    admin = create(:user, :admin)
    participant_group = create(:participant_group, :school_election)
    slot = create(:participant_slot, participant_group: participant_group)
    return_to = schools_path
    sign_in admin

    get edit_participant_group_roster_path(participant_group, return_to: return_to)

    expect(response.body).to include(participant_group_roster_path(participant_group, return_to: return_to))

    patch participant_group_roster_path(participant_group, return_to: return_to), params: {
      roster: { slots: { "0" => { id: slot.id, number: slot.number, name: "수정 학생" } } }
    }

    expect(response).to redirect_to(participant_group_path(participant_group, return_to: return_to))
  end

  it "supports swapping student numbers in one update" do
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    first = create(:participant_slot, participant_group: participant_group, number: 1, name: "첫째")
    second = create(:participant_slot, participant_group: participant_group, number: 2, name: "둘째")
    sign_in teacher

    patch participant_group_roster_path(participant_group), params: {
      roster: {
        slots: {
          "0" => { id: first.id, number: 2, name: "첫째 수정" },
          "1" => { id: second.id, number: 1, name: "둘째 수정" }
        }
      }
    }

    expect(response).to redirect_to(participant_group_path(participant_group))
    expect(first.reload).to have_attributes(number: 2, name: "첫째 수정")
    expect(second.reload).to have_attributes(number: 1, name: "둘째 수정")
  end

  it "lets a teacher edit students in their school election roster" do
    teacher = create(:user)
    participant_group = create(:participant_group, :school_election, user: teacher)
    slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "학생")
    sign_in teacher

    patch participant_group_roster_path(participant_group), params: {
      roster: { slots: { "0" => { id: slot.id, number: 3, name: "학생 수정" } } }
    }

    expect(response).to redirect_to(participant_group_path(participant_group))
    expect(slot.reload).to have_attributes(number: 3, name: "학생 수정")
  end

  it "rejects duplicate numbers with a clear error" do
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    first = create(:participant_slot, participant_group: participant_group, number: 1)
    second = create(:participant_slot, participant_group: participant_group, number: 2)
    sign_in teacher

    patch participant_group_roster_path(participant_group), params: {
      roster: {
        slots: {
          "0" => { id: first.id, number: 1, name: first.name },
          "1" => { id: second.id, number: 1, name: second.name }
        }
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("같은 번호가 있습니다.")
    expect(first.reload.number).to eq(1)
    expect(second.reload.number).to eq(2)
  end
end
