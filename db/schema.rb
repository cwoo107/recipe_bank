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

ActiveRecord::Schema[8.1].define(version: 2026_02_13_211226) do
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

  create_table "grocery_lists", force: :cascade do |t|
    t.boolean "checked"
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.boolean "manually_adjusted"
    t.text "meal_ids"
    t.integer "units"
    t.datetime "updated_at", null: false
    t.date "week_of"
    t.index ["ingredient_id"], name: "index_grocery_lists_on_ingredient_id"
  end

  create_table "household_members", force: :cascade do |t|
    t.boolean "child"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_household_members_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "family_name"
    t.datetime "updated_at", null: false
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
    t.string "family"
    t.string "ingredient"
    t.boolean "organic"
    t.float "unit_price"
    t.integer "unit_servings"
    t.datetime "updated_at", null: false
  end

  create_table "meals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "meal_name"
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_meals_on_recipe_id"
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
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "grocery_lists", "ingredients"
  add_foreign_key "household_members", "households"
  add_foreign_key "ingredient_tags", "ingredients"
  add_foreign_key "ingredient_tags", "tags"
  add_foreign_key "meals", "recipes"
  add_foreign_key "nutrition_facts", "ingredients"
  add_foreign_key "recipe_ingredients", "ingredients"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_tags", "recipes"
  add_foreign_key "recipe_tags", "tags"
  add_foreign_key "steps", "recipes"
end
