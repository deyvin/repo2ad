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

ActiveRecord::Schema[8.1].define(version: 2026_11_24_191403) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "creatives", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "code"
    t.string "group"
    t.string "recipe"
    t.string "aspect_ratio"
    t.integer "duration"
    t.string "title"
    t.json "concept"
    t.boolean "selected", default: false, null: false
    t.string "status"
    t.json "spec"
    t.json "qa"
    t.text "instructions"
    t.integer "attempts", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_creatives_on_project_id"
  end

  create_table "media_inputs", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "source"
    t.string "path"
    t.string "kind"
    t.text "description"
    t.integer "width"
    t.integer "height"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_media_inputs_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "repo_url"
    t.string "owner"
    t.string "name"
    t.string "commit_sha"
    t.string "status"
    t.json "brief"
    t.json "audience"
    t.json "angles"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "render_steps", force: :cascade do |t|
    t.integer "creative_id", null: false
    t.string "name"
    t.string "kind"
    t.string "model"
    t.json "params"
    t.string "hf_job_id"
    t.string "status"
    t.integer "poll_attempts", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creative_id"], name: "index_render_steps_on_creative_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "creatives", "projects"
  add_foreign_key "media_inputs", "projects"
  add_foreign_key "render_steps", "creatives"
end
