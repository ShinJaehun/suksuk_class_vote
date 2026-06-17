# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_17_030000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "participant_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_participant_groups_on_user_id"
  end

  create_table "participant_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "participant_group_id", null: false
    t.datetime "updated_at", null: false
    t.index ["participant_group_id", "number"], name: "index_participant_slots_on_participant_group_id_and_number", unique: true
    t.index ["participant_group_id"], name: "index_participant_slots_on_participant_group_id"
  end

  create_table "poll_contests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "poll_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_id", "position"], name: "index_poll_contests_on_poll_id_and_position", unique: true
    t.index ["poll_id"], name: "index_poll_contests_on_poll_id"
  end

  create_table "poll_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.bigint "poll_id", null: false
    t.bigint "poll_participant_id"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_poll_events_on_actor_id"
    t.index ["event_type"], name: "index_poll_events_on_event_type"
    t.index ["poll_id", "occurred_at"], name: "index_poll_events_on_poll_id_and_occurred_at"
    t.index ["poll_id"], name: "index_poll_events_on_poll_id"
    t.index ["poll_participant_id"], name: "index_poll_events_on_poll_participant_id"
  end

  create_table "poll_option_tallies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "poll_id", null: false
    t.bigint "poll_option_id", null: false
    t.datetime "updated_at", null: false
    t.integer "votes_count", default: 0, null: false
    t.index ["poll_id", "poll_option_id"], name: "index_poll_option_tallies_on_poll_id_and_poll_option_id", unique: true
    t.index ["poll_id"], name: "index_poll_option_tallies_on_poll_id"
    t.index ["poll_option_id"], name: "index_poll_option_tallies_on_poll_option_id"
  end

  create_table "poll_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "poll_contest_id", null: false
    t.bigint "poll_id", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_contest_id", "number"], name: "index_poll_options_on_poll_contest_id_and_number", unique: true
    t.index ["poll_contest_id"], name: "index_poll_options_on_poll_contest_id"
    t.index ["poll_id"], name: "index_poll_options_on_poll_id"
  end

  create_table "poll_participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "poll_id", null: false
    t.bigint "source_participant_slot_id"
    t.datetime "updated_at", null: false
    t.index ["poll_id", "number"], name: "index_poll_participants_on_poll_id_and_number", unique: true
    t.index ["poll_id", "source_participant_slot_id"], name: "idx_on_poll_id_source_participant_slot_id_4913eb3601", unique: true
    t.index ["poll_id"], name: "index_poll_participants_on_poll_id"
    t.index ["source_participant_slot_id"], name: "index_poll_participants_on_source_participant_slot_id"
  end

  create_table "poll_participations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "poll_participant_id", null: false
    t.datetime "recorded_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["poll_participant_id"], name: "index_poll_participations_on_poll_participant_id", unique: true
  end

  create_table "poll_progresses", force: :cascade do |t|
    t.integer "ballot_status", default: 0, null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "current_poll_participant_id"
    t.bigint "poll_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["current_poll_participant_id"], name: "index_poll_progresses_on_current_poll_participant_id"
    t.index ["poll_id"], name: "index_poll_progresses_on_poll_id", unique: true
  end

  create_table "polls", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.bigint "participant_group_id"
    t.string "participant_group_name_snapshot"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["archived_at"], name: "index_polls_on_archived_at"
    t.index ["participant_group_id"], name: "index_polls_on_participant_group_id"
    t.index ["user_id"], name: "index_polls_on_user_id"
  end

  create_table "school_election_candidates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "grade_class_label", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "school_election_contest_id", null: false
    t.datetime "updated_at", null: false
    t.index ["school_election_contest_id", "number"], name: "idx_on_school_election_contest_id_number_f0c4e1e975", unique: true
    t.index ["school_election_contest_id"], name: "index_school_election_candidates_on_school_election_contest_id"
  end

  create_table "school_election_classroom_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "participant_group_id", null: false
    t.bigint "poll_id"
    t.bigint "school_election_id", null: false
    t.bigint "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.index ["participant_group_id"], name: "idx_on_participant_group_id_e3234fdf3f"
    t.index ["poll_id"], name: "index_school_election_classroom_sessions_on_poll_id", unique: true
    t.index ["school_election_id", "participant_group_id"], name: "idx_school_election_sessions_on_election_and_group", unique: true
    t.index ["school_election_id"], name: "index_school_election_classroom_sessions_on_school_election_id"
    t.index ["teacher_id"], name: "index_school_election_classroom_sessions_on_teacher_id"
  end

  create_table "school_election_contests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "school_election_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["school_election_id", "position"], name: "idx_on_school_election_id_position_55289be15a", unique: true
    t.index ["school_election_id"], name: "index_school_election_contests_on_school_election_id"
  end

  create_table "school_elections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status"], name: "index_school_elections_on_status"
    t.index ["user_id"], name: "index_school_elections_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "participant_groups", "users"
  add_foreign_key "participant_slots", "participant_groups"
  add_foreign_key "poll_contests", "polls"
  add_foreign_key "poll_events", "poll_participants"
  add_foreign_key "poll_events", "polls"
  add_foreign_key "poll_events", "users", column: "actor_id"
  add_foreign_key "poll_option_tallies", "poll_options"
  add_foreign_key "poll_option_tallies", "polls"
  add_foreign_key "poll_options", "poll_contests"
  add_foreign_key "poll_options", "polls"
  add_foreign_key "poll_participants", "participant_slots", column: "source_participant_slot_id", on_delete: :nullify
  add_foreign_key "poll_participants", "polls"
  add_foreign_key "poll_participations", "poll_participants"
  add_foreign_key "poll_progresses", "poll_participants", column: "current_poll_participant_id"
  add_foreign_key "poll_progresses", "polls"
  add_foreign_key "polls", "participant_groups", on_delete: :nullify
  add_foreign_key "polls", "users"
  add_foreign_key "school_election_candidates", "school_election_contests"
  add_foreign_key "school_election_classroom_sessions", "participant_groups"
  add_foreign_key "school_election_classroom_sessions", "polls"
  add_foreign_key "school_election_classroom_sessions", "school_elections"
  add_foreign_key "school_election_classroom_sessions", "users", column: "teacher_id"
  add_foreign_key "school_election_contests", "school_elections"
  add_foreign_key "school_elections", "users"
end
