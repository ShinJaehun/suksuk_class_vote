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

ActiveRecord::Schema[8.1].define(version: 2026_08_20_180000) do
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

  create_table "poll_contest_completions", force: :cascade do |t|
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "poll_contest_id", null: false
    t.bigint "poll_participant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_contest_id"], name: "index_poll_contest_completions_on_poll_contest_id"
    t.index ["poll_participant_id", "poll_contest_id"], name: "idx_poll_contest_completions_participant_contest", unique: true
    t.index ["poll_participant_id"], name: "index_poll_contest_completions_on_poll_participant_id"
  end

  create_table "poll_contest_tallies", force: :cascade do |t|
    t.integer "abstentions_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "poll_contest_id", null: false
    t.bigint "poll_id", null: false
    t.bigint "poll_session_id", null: false
    t.integer "rejections_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["poll_contest_id"], name: "index_poll_contest_tallies_on_poll_contest_id"
    t.index ["poll_id"], name: "index_poll_contest_tallies_on_poll_id"
    t.index ["poll_session_id", "poll_contest_id"], name: "idx_poll_contest_tallies_session_contest", unique: true
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
    t.bigint "poll_session_id"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_poll_events_on_actor_id"
    t.index ["event_type"], name: "index_poll_events_on_event_type"
    t.index ["poll_id", "occurred_at"], name: "index_poll_events_on_poll_id_and_occurred_at"
    t.index ["poll_id"], name: "index_poll_events_on_poll_id"
    t.index ["poll_participant_id"], name: "index_poll_events_on_poll_participant_id"
    t.index ["poll_session_id"], name: "index_poll_events_on_poll_session_id"
  end

  create_table "poll_option_tallies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "poll_id", null: false
    t.bigint "poll_option_id", null: false
    t.bigint "poll_session_id", null: false
    t.datetime "updated_at", null: false
    t.integer "votes_count", default: 0, null: false
    t.index ["poll_id"], name: "index_poll_option_tallies_on_poll_id"
    t.index ["poll_option_id"], name: "index_poll_option_tallies_on_poll_option_id"
    t.index ["poll_session_id", "poll_option_id"], name: "idx_poll_option_tallies_session_option", unique: true
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
    t.bigint "poll_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_id"], name: "index_poll_participants_on_poll_id"
    t.index ["poll_session_id", "number"], name: "idx_poll_participants_session_number", unique: true
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
    t.bigint "poll_session_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["current_poll_participant_id"], name: "index_poll_progresses_on_current_poll_participant_id"
    t.index ["poll_session_id"], name: "idx_poll_progresses_session", unique: true
  end

  create_table "poll_sessions", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "classroom_id", null: false
    t.string "classroom_name_snapshot", null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "operator_id", null: false
    t.string "operator_name_snapshot", null: false
    t.bigint "poll_id", null: false
    t.bigint "replacement_of_id"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "stopped_at"
    t.datetime "updated_at", null: false
    t.index ["classroom_id"], name: "index_poll_sessions_on_classroom_id"
    t.index ["operator_id"], name: "index_poll_sessions_on_operator_id"
    t.index ["poll_id", "classroom_id"], name: "idx_poll_sessions_active_poll_classroom", unique: true, where: "(status = ANY (ARRAY[0, 10]))"
    t.index ["poll_id"], name: "index_poll_sessions_on_poll_id"
    t.index ["replacement_of_id"], name: "index_poll_sessions_on_replacement_of_id", unique: true
    t.check_constraint "replacement_of_id IS NULL OR replacement_of_id <> id", name: "chk_poll_sessions_replacement_not_self"
    t.check_constraint "status = ANY (ARRAY[0, 10, 20, 30])", name: "chk_poll_sessions_status"
  end

  create_table "polls", force: :cascade do |t|
    t.boolean "abstention_allowed", default: true, null: false
    t.integer "advancement_mode", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.boolean "referendum_allowed", default: false, null: false
    t.bigint "school_id"
    t.boolean "school_managed", default: false, null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "stopped_at"
    t.bigint "test_source_poll_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["archived_at"], name: "index_polls_on_archived_at"
    t.index ["school_id"], name: "index_polls_on_school_id"
    t.index ["test_source_poll_id"], name: "index_polls_on_test_source_poll_id"
    t.index ["user_id"], name: "index_polls_on_user_id"
  end

  create_table "school_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "grade"
    t.integer "role", default: 0, null: false
    t.bigint "school_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["school_id", "grade"], name: "index_school_memberships_on_school_id_and_grade"
    t.index ["school_id"], name: "index_school_memberships_on_school_id"
    t.index ["school_id"], name: "index_school_memberships_on_unique_manager", unique: true, where: "(role = 10)"
    t.index ["user_id"], name: "index_school_memberships_on_user_id", unique: true
    t.check_constraint "grade IS NULL OR grade >= 1 AND grade <= 6", name: "school_memberships_grade_allowed"
  end

  create_table "schools", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "color_key", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_schools_on_name", unique: true
    t.check_constraint "color_key::text = ANY (ARRAY['rose'::character varying, 'amber'::character varying, 'emerald'::character varying, 'sky'::character varying, 'violet'::character varying]::text[])", name: "schools_color_key_allowed"
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
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "login_id", null: false
    t.string "name", default: "", null: false
    t.boolean "password_change_required", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index "lower((login_id)::text)", name: "index_users_on_lower_login_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id", on_delete: :nullify
  add_foreign_key "poll_contest_completions", "poll_contests"
  add_foreign_key "poll_contest_completions", "poll_participants"
  add_foreign_key "poll_contest_tallies", "poll_contests"
  add_foreign_key "poll_contest_tallies", "poll_sessions"
  add_foreign_key "poll_contest_tallies", "polls"
  add_foreign_key "poll_contests", "polls"
  add_foreign_key "poll_events", "poll_participants"
  add_foreign_key "poll_events", "poll_sessions"
  add_foreign_key "poll_events", "polls"
  add_foreign_key "poll_events", "users", column: "actor_id"
  add_foreign_key "poll_option_tallies", "poll_options"
  add_foreign_key "poll_option_tallies", "poll_sessions"
  add_foreign_key "poll_option_tallies", "polls"
  add_foreign_key "poll_options", "poll_contests"
  add_foreign_key "poll_options", "polls"
  add_foreign_key "poll_participants", "poll_sessions"
  add_foreign_key "poll_participants", "polls"
  add_foreign_key "poll_participations", "poll_participants"
  add_foreign_key "poll_progresses", "poll_participants", column: "current_poll_participant_id"
  add_foreign_key "poll_progresses", "poll_sessions"
  add_foreign_key "poll_progresses", "polls"
  add_foreign_key "poll_sessions", "classrooms"
  add_foreign_key "poll_sessions", "poll_sessions", column: "replacement_of_id"
  add_foreign_key "poll_sessions", "polls"
  add_foreign_key "poll_sessions", "users", column: "operator_id"
  add_foreign_key "polls", "polls", column: "test_source_poll_id"
  add_foreign_key "polls", "schools"
  add_foreign_key "polls", "users"
  add_foreign_key "school_memberships", "schools"
  add_foreign_key "school_memberships", "users"
  add_foreign_key "students", "classrooms"
end
