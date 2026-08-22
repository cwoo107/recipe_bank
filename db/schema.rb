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

ActiveRecord::Schema[8.1].define(version: 2026_07_02_190043) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

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

  create_table "calendar_events", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.integer "calendar_source_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at", null: false
    t.string "external_uid"
    t.string "location"
    t.string "recurrence_rule"
    t.datetime "starts_at", null: false
    t.string "status", default: "confirmed"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["calendar_source_id", "starts_at"], name: "index_calendar_events_on_calendar_source_id_and_starts_at"
    t.index ["calendar_source_id"], name: "index_calendar_events_on_calendar_source_id"
    t.index ["ends_at"], name: "index_calendar_events_on_ends_at"
    t.index ["external_uid"], name: "index_calendar_events_on_external_uid"
    t.index ["starts_at"], name: "index_calendar_events_on_starts_at"
    t.index ["user_id", "starts_at"], name: "index_calendar_events_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_calendar_events_on_user_id"
  end

  create_table "calendar_sources", force: :cascade do |t|
    t.string "access_token"
    t.string "color", default: "olive", null: false
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "ical_url"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "provider", null: false
    t.string "refresh_token"
    t.boolean "synced", default: false, null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible", default: true, null: false
    t.index ["provider"], name: "index_calendar_sources_on_provider"
    t.index ["user_id", "position"], name: "index_calendar_sources_on_user_id_and_position"
    t.index ["user_id"], name: "index_calendar_sources_on_user_id"
  end

  create_table "collection_recipes", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.datetime "created_at", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_collection_recipes_on_collection_id"
    t.index ["recipe_id"], name: "index_collection_recipes_on_recipe_id"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "public"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_collections_on_user_id"
  end

  create_table "grocery_lists", force: :cascade do |t|
    t.boolean "checked"
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.boolean "manually_adjusted"
    t.text "meal_ids"
    t.integer "units"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.date "week_of"
    t.index ["ingredient_id"], name: "index_grocery_lists_on_ingredient_id"
    t.index ["user_id"], name: "index_grocery_lists_on_user_id"
  end

  create_table "household_members", force: :cascade do |t|
    t.boolean "child"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name"
    t.integer "role", default: 1, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["household_id"], name: "index_household_members_on_household_id"
    t.index ["user_id"], name: "index_household_members_on_user_id", unique: true
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "family_name"
    t.integer "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_households_on_owner_id"
  end

  create_table "ingredient_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_ingredient_tags_on_ingredient_id"
    t.index ["tag_id"], name: "index_ingredient_tags_on_tag_id"
  end

  create_table "ingredients", force: :cascade do |t|
    t.string "brand"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "family"
    t.boolean "favorite"
    t.string "ingredient"
    t.boolean "organic"
    t.float "unit_price"
    t.integer "unit_servings"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_ingredients_on_created_by_id"
  end

  create_table "meals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "meal_name"
    t.integer "recipe_id", null: false
    t.integer "servings"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["recipe_id"], name: "index_meals_on_recipe_id"
    t.index ["user_id"], name: "index_meals_on_user_id"
  end

  create_table "nutrition_facts", force: :cascade do |t|
    t.integer "calories"
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.float "protein"
    t.float "serving_size"
    t.string "serving_unit"
    t.float "total_carb"
    t.float "total_fat"
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_nutrition_facts_on_ingredient_id"
  end

  create_table "recipe_import_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "current_step"
    t.text "error_message"
    t.json "matched_ingredients"
    t.integer "progress", default: 0
    t.integer "recipe_id"
    t.json "scraped_data"
    t.string "status", default: "pending", null: false
    t.integer "total_steps", default: 5
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id"
    t.index ["user_id"], name: "index_recipe_import_jobs_on_user_id"
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.float "quantity"
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_recipe_ingredients_on_ingredient_id"
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
  end

  create_table "recipe_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "recipe_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_recipe_tags_on_recipe_id"
    t.index ["tag_id"], name: "index_recipe_tags_on_tag_id"
  end

  create_table "recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "servings"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "visibility", default: "public", null: false
    t.index ["user_id", "visibility"], name: "index_recipes_on_user_id_and_visibility"
    t.index ["user_id"], name: "index_recipes_on_user_id"
    t.index ["visibility"], name: "index_recipes_on_visibility"
  end

  create_table "steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position"
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_steps_on_recipe_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "tag"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "todos", force: :cascade do |t|
    t.integer "actual_time_to_complete"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_date"
    t.integer "estimated_time_to_complete"
    t.integer "position", default: 0, null: false
    t.integer "priority", null: false
    t.datetime "start_date"
    t.string "status", default: "todo", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "status", "position"], name: "index_todos_on_user_id_and_status_and_position"
    t.index ["user_id", "status", "start_date"], name: "index_todos_on_user_id_and_status_and_start_date"
    t.index ["user_id", "status"], name: "index_todos_on_user_id_and_status"
    t.index ["user_id"], name: "index_todos_on_user_id"
  end

  create_table "user_favorites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["recipe_id"], name: "index_user_favorites_on_recipe_id"
    t.index ["user_id", "recipe_id"], name: "index_user_favorites_on_user_id_and_recipe_id", unique: true
    t.index ["user_id"], name: "index_user_favorites_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "calendar_events", "calendar_sources"
  add_foreign_key "calendar_events", "users"
  add_foreign_key "calendar_sources", "users"
  add_foreign_key "collection_recipes", "collections"
  add_foreign_key "collection_recipes", "recipes"
  add_foreign_key "collections", "users"
  add_foreign_key "grocery_lists", "ingredients"
  add_foreign_key "grocery_lists", "users"
  add_foreign_key "household_members", "households"
  add_foreign_key "household_members", "users"
  add_foreign_key "households", "users", column: "owner_id"
  add_foreign_key "ingredient_tags", "ingredients"
  add_foreign_key "ingredient_tags", "tags"
  add_foreign_key "ingredients", "users", column: "created_by_id"
  add_foreign_key "meals", "recipes"
  add_foreign_key "meals", "users"
  add_foreign_key "nutrition_facts", "ingredients"
  add_foreign_key "recipe_import_jobs", "users"
  add_foreign_key "recipe_ingredients", "ingredients"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_tags", "recipes"
  add_foreign_key "recipe_tags", "tags"
  add_foreign_key "recipes", "users"
  add_foreign_key "steps", "recipes"
  add_foreign_key "tags", "users"
  add_foreign_key "todos", "users"
  add_foreign_key "user_favorites", "recipes"
  add_foreign_key "user_favorites", "users"
end
