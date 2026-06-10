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

ActiveRecord::Schema[8.1].define(version: 2026_06_10_030000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.bigint "poll_id", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_id", "number"], name: "index_poll_options_on_poll_id_and_number", unique: true
    t.index ["poll_id"], name: "index_poll_options_on_poll_id"
  end

  create_table "poll_participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "poll_id", null: false
    t.bigint "source_voter_slot_id"
    t.datetime "updated_at", null: false
    t.index ["poll_id", "number"], name: "index_poll_participants_on_poll_id_and_number", unique: true
    t.index ["poll_id", "source_voter_slot_id"], name: "index_poll_participants_on_poll_id_and_source_voter_slot_id", unique: true
    t.index ["poll_id"], name: "index_poll_participants_on_poll_id"
    t.index ["source_voter_slot_id"], name: "index_poll_participants_on_source_voter_slot_id"
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
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "voter_group_id"
    t.string "voter_group_name_snapshot"
    t.index ["user_id"], name: "index_polls_on_user_id"
    t.index ["voter_group_id"], name: "index_polls_on_voter_group_id"
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

  create_table "voter_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_voter_groups_on_user_id"
  end

  create_table "voter_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.datetime "updated_at", null: false
    t.bigint "voter_group_id", null: false
    t.index ["voter_group_id", "number"], name: "index_voter_slots_on_voter_group_id_and_number", unique: true
    t.index ["voter_group_id"], name: "index_voter_slots_on_voter_group_id"
  end

  add_foreign_key "poll_events", "poll_participants"
  add_foreign_key "poll_events", "polls"
  add_foreign_key "poll_events", "users", column: "actor_id"
  add_foreign_key "poll_option_tallies", "poll_options"
  add_foreign_key "poll_option_tallies", "polls"
  add_foreign_key "poll_options", "polls"
  add_foreign_key "poll_participants", "polls"
  add_foreign_key "poll_participants", "voter_slots", column: "source_voter_slot_id", on_delete: :nullify
  add_foreign_key "poll_participations", "poll_participants"
  add_foreign_key "poll_progresses", "poll_participants", column: "current_poll_participant_id"
  add_foreign_key "poll_progresses", "polls"
  add_foreign_key "polls", "users"
  add_foreign_key "polls", "voter_groups", on_delete: :nullify
  add_foreign_key "voter_groups", "users"
  add_foreign_key "voter_slots", "voter_groups"
end
