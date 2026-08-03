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

ActiveRecord::Schema[8.1].define(version: 2026_08_03_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "classrooms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "class_label", null: false
    t.datetime "created_at", null: false
    t.integer "grade", null: false
    t.string "name", null: false
    t.bigint "school_id", null: false
    t.integer "school_year", null: false
    t.bigint "teacher_id"
    t.datetime "updated_at", null: false
    t.index ["school_id", "school_year", "grade", "class_label"], name: "idx_classrooms_on_school_year_grade_label", unique: true
    t.index ["school_id"], name: "index_classrooms_on_school_id"
    t.index ["teacher_id"], name: "idx_classrooms_on_active_teacher", unique: true, where: "((active = true) AND (teacher_id IS NOT NULL))"
  end

  create_table "election_candidate_tallies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "election_candidate_id", null: false
    t.bigint "election_contest_id", null: false
    t.bigint "election_session_id", null: false
    t.datetime "updated_at", null: false
    t.integer "votes_count", default: 0, null: false
    t.index ["election_candidate_id"], name: "index_election_candidate_tallies_on_election_candidate_id"
    t.index ["election_contest_id"], name: "index_election_candidate_tallies_on_election_contest_id"
    t.index ["election_session_id", "election_candidate_id"], name: "idx_on_election_session_id_election_candidate_id_66ddcf35f8", unique: true
    t.index ["election_session_id", "election_contest_id"], name: "idx_on_election_session_id_election_contest_id_0cfb705005"
    t.index ["election_session_id"], name: "index_election_candidate_tallies_on_election_session_id"
  end

  create_table "election_candidates", force: :cascade do |t|
    t.string "affiliation_label"
    t.datetime "created_at", null: false
    t.bigint "election_contest_id", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.datetime "updated_at", null: false
    t.index ["election_contest_id", "number"], name: "index_election_candidates_on_election_contest_id_and_number", unique: true
    t.index ["election_contest_id"], name: "index_election_candidates_on_election_contest_id"
  end

  create_table "election_contest_tallies", force: :cascade do |t|
    t.integer "abstentions_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "election_contest_id", null: false
    t.bigint "election_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["election_contest_id"], name: "index_election_contest_tallies_on_election_contest_id"
    t.index ["election_session_id", "election_contest_id"], name: "idx_on_election_session_id_election_contest_id_69e6b91ae1", unique: true
    t.index ["election_session_id"], name: "index_election_contest_tallies_on_election_session_id"
  end

  create_table "election_contests", force: :cascade do |t|
    t.boolean "allow_abstain", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "election_id", null: false
    t.integer "max_selections", default: 1, null: false
    t.integer "min_selections", default: 1, null: false
    t.integer "position", null: false
    t.integer "seats_count", default: 1, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "vote_method", default: 0, null: false
    t.index ["election_id", "position"], name: "index_election_contests_on_election_id_and_position", unique: true
    t.index ["election_id"], name: "index_election_contests_on_election_id"
  end

  create_table "election_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.bigint "election_session_id", null: false
    t.bigint "election_voter_id"
    t.integer "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_election_events_on_actor_id"
    t.index ["election_session_id", "occurred_at"], name: "index_election_events_on_election_session_id_and_occurred_at"
    t.index ["election_session_id"], name: "index_election_events_on_election_session_id"
    t.index ["election_voter_id"], name: "index_election_events_on_election_voter_id"
    t.index ["event_type"], name: "index_election_events_on_event_type"
  end

  create_table "election_participations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "election_voter_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["election_voter_id"], name: "index_election_participations_on_election_voter_id", unique: true
    t.index ["status"], name: "index_election_participations_on_status"
  end

  create_table "election_progresses", force: :cascade do |t|
    t.integer "ballot_state", default: 0, null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "current_election_voter_id"
    t.bigint "election_session_id", null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.index ["ballot_state"], name: "index_election_progresses_on_ballot_state"
    t.index ["current_election_voter_id"], name: "index_election_progresses_on_current_election_voter_id"
    t.index ["election_session_id"], name: "index_election_progresses_on_election_session_id", unique: true
  end

  create_table "election_sessions", force: :cascade do |t|
    t.bigint "classroom_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "election_id", null: false
    t.datetime "hidden_from_teacher_at"
    t.integer "operation_mode", default: 0, null: false
    t.bigint "participant_group_id"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "stopped_at"
    t.bigint "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id"], name: "index_election_sessions_on_classroom_id"
    t.index ["election_id", "classroom_id"], name: "idx_election_sessions_active_classroom", unique: true, where: "(status = ANY (ARRAY[0, 10]))"
    t.index ["election_id", "participant_group_id"], name: "index_election_sessions_on_active_group_assignment", unique: true, where: "(status = ANY (ARRAY[0, 10]))"
    t.index ["election_id"], name: "index_election_sessions_on_election_id"
    t.index ["operation_mode"], name: "index_election_sessions_on_operation_mode"
    t.index ["participant_group_id"], name: "index_election_sessions_on_participant_group_id"
    t.index ["status"], name: "index_election_sessions_on_status"
    t.index ["teacher_id"], name: "index_election_sessions_on_teacher_id"
    t.check_constraint "participant_group_id IS NOT NULL AND classroom_id IS NULL OR participant_group_id IS NULL AND classroom_id IS NOT NULL", name: "chk_election_sessions_one_source"
  end

  create_table "election_voters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "election_session_id", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.integer "position", null: false
    t.bigint "source_participant_slot_id"
    t.datetime "updated_at", null: false
    t.index ["election_session_id", "number"], name: "index_election_voters_on_election_session_id_and_number", unique: true
    t.index ["election_session_id", "position"], name: "index_election_voters_on_election_session_id_and_position", unique: true
    t.index ["election_session_id", "source_participant_slot_id"], name: "idx_on_election_session_id_source_participant_slot__637965b3c2", unique: true, where: "(source_participant_slot_id IS NOT NULL)"
    t.index ["election_session_id"], name: "index_election_voters_on_election_session_id"
    t.index ["source_participant_slot_id"], name: "index_election_voters_on_source_participant_slot_id"
  end

  create_table "elections", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.bigint "school_id"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "stopped_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["kind"], name: "index_elections_on_kind"
    t.index ["school_id"], name: "index_elections_on_school_id"
    t.index ["status"], name: "index_elections_on_status"
    t.index ["user_id"], name: "index_elections_on_user_id"
  end

  create_table "participant_groups", force: :cascade do |t|
    t.string "class_label"
    t.integer "class_number"
    t.datetime "created_at", null: false
    t.integer "grade"
    t.string "name", null: false
    t.integer "purpose", default: 0, null: false
    t.bigint "school_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["purpose", "grade", "class_number"], name: "index_participant_groups_on_purpose_and_grade_and_class_number"
    t.index ["purpose"], name: "index_participant_groups_on_purpose"
    t.index ["school_id", "purpose", "grade", "class_label"], name: "idx_on_school_id_purpose_grade_class_label_6233e209ee"
    t.index ["school_id"], name: "index_participant_groups_on_school_id"
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

  create_table "poll_contest_tallies", force: :cascade do |t|
    t.integer "abstentions_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "poll_contest_id", null: false
    t.bigint "poll_id", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_contest_id"], name: "index_poll_contest_tallies_on_poll_contest_id"
    t.index ["poll_id", "poll_contest_id"], name: "index_poll_contest_tallies_on_poll_id_and_poll_contest_id", unique: true
    t.index ["poll_id"], name: "index_poll_contest_tallies_on_poll_id"
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

  create_table "school_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.bigint "school_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["school_id"], name: "index_school_memberships_on_school_id"
    t.index ["user_id"], name: "index_school_memberships_on_user_id", unique: true
  end

  create_table "schools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_schools_on_name", unique: true
  end

  create_table "students", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "number"], name: "index_students_on_classroom_id_and_number", unique: true
    t.index ["classroom_id"], name: "index_students_on_classroom_id"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id", on_delete: :nullify
  add_foreign_key "election_candidate_tallies", "election_candidates"
  add_foreign_key "election_candidate_tallies", "election_contests"
  add_foreign_key "election_candidate_tallies", "election_sessions"
  add_foreign_key "election_candidates", "election_contests"
  add_foreign_key "election_contest_tallies", "election_contests"
  add_foreign_key "election_contest_tallies", "election_sessions"
  add_foreign_key "election_contests", "elections"
  add_foreign_key "election_events", "election_sessions"
  add_foreign_key "election_events", "election_voters", on_delete: :nullify
  add_foreign_key "election_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "election_participations", "election_voters"
  add_foreign_key "election_progresses", "election_sessions"
  add_foreign_key "election_progresses", "election_voters", column: "current_election_voter_id", on_delete: :nullify
  add_foreign_key "election_sessions", "classrooms"
  add_foreign_key "election_sessions", "elections"
  add_foreign_key "election_sessions", "participant_groups"
  add_foreign_key "election_sessions", "users", column: "teacher_id"
  add_foreign_key "election_voters", "election_sessions"
  add_foreign_key "election_voters", "participant_slots", column: "source_participant_slot_id", on_delete: :nullify
  add_foreign_key "elections", "schools"
  add_foreign_key "elections", "users"
  add_foreign_key "participant_groups", "schools"
  add_foreign_key "participant_groups", "users"
  add_foreign_key "participant_slots", "participant_groups"
  add_foreign_key "poll_contest_tallies", "poll_contests"
  add_foreign_key "poll_contest_tallies", "polls"
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
  add_foreign_key "school_memberships", "schools"
  add_foreign_key "school_memberships", "users"
  add_foreign_key "students", "classrooms"
end
