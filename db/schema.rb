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

ActiveRecord::Schema[8.1].define(version: 2026_06_06_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "candidates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "election_id", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id", "number"], name: "index_candidates_on_election_id_and_number", unique: true
    t.index ["election_id"], name: "index_candidates_on_election_id"
  end

  create_table "election_voters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "election_id", null: false
    t.string "name", null: false
    t.integer "number", null: false
    t.bigint "source_voter_slot_id", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id", "number"], name: "index_election_voters_on_election_id_and_number", unique: true
    t.index ["election_id", "source_voter_slot_id"], name: "index_election_voters_on_election_id_and_source_voter_slot_id", unique: true
    t.index ["election_id"], name: "index_election_voters_on_election_id"
    t.index ["source_voter_slot_id"], name: "index_election_voters_on_source_voter_slot_id"
  end

  create_table "elections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "voter_group_id", null: false
    t.index ["user_id"], name: "index_elections_on_user_id"
    t.index ["voter_group_id"], name: "index_elections_on_voter_group_id"
  end

  create_table "polling_stations", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "current_election_voter_id"
    t.bigint "election_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["current_election_voter_id"], name: "index_polling_stations_on_current_election_voter_id"
    t.index ["election_id"], name: "index_polling_stations_on_election_id", unique: true
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

  add_foreign_key "candidates", "elections"
  add_foreign_key "election_voters", "elections"
  add_foreign_key "election_voters", "voter_slots", column: "source_voter_slot_id"
  add_foreign_key "elections", "users"
  add_foreign_key "elections", "voter_groups"
  add_foreign_key "polling_stations", "election_voters", column: "current_election_voter_id"
  add_foreign_key "polling_stations", "elections"
  add_foreign_key "voter_groups", "users"
  add_foreign_key "voter_slots", "voter_groups"
end
