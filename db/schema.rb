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

ActiveRecord::Schema[7.1].define(version: 2026_09_20_220949) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.bigint "import_run_id", null: false
    t.string "event_type", null: false
    t.string "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["import_run_id", "created_at"], name: "index_audit_events_on_import_run_id_and_created_at"
    t.index ["import_run_id"], name: "index_audit_events_on_import_run_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_companies_on_external_id", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "external_id"], name: "index_departments_on_company_and_external_id", unique: true
    t.index ["company_id"], name: "index_departments_on_company_id"
  end

  create_table "employee_contracts", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.date "start_date", null: false
    t.date "end_date"
    t.integer "salary_cents", null: false
    t.string "contract_type", default: "permanent", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "start_date"], name: "index_employee_contracts_on_employee_id_and_start_date"
    t.index ["employee_id"], name: "index_employee_contracts_on_employee_id"
  end

  create_table "employees", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "department_id"
    t.bigint "manager_id"
    t.string "external_id", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email"
    t.date "start_date"
    t.integer "gross_salary_cents"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "external_id"], name: "index_employees_on_company_and_external_id", unique: true
    t.index ["company_id", "manager_id"], name: "index_employees_on_company_id_and_manager_id"
    t.index ["company_id"], name: "index_employees_on_company_id"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.check_constraint "gross_salary_cents IS NULL OR gross_salary_cents >= 0", name: "employees_gross_salary_non_negative"
  end

  create_table "import_issues", force: :cascade do |t|
    t.bigint "import_run_id", null: false
    t.integer "row_number"
    t.string "external_id"
    t.string "issue_type", null: false
    t.string "severity", null: false
    t.string "field_name"
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_run_id", "issue_type"], name: "index_import_issues_on_import_run_id_and_issue_type"
    t.index ["import_run_id", "severity"], name: "index_import_issues_on_import_run_id_and_severity"
    t.index ["import_run_id"], name: "index_import_issues_on_import_run_id"
    t.check_constraint "severity::text = ANY (ARRAY['warning'::character varying, 'blocking'::character varying]::text[])", name: "import_issues_severity_check"
  end

  create_table "import_runs", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "filename", null: false
    t.string "status", default: "uploaded", null: false
    t.integer "source_record_count", default: 0, null: false
    t.integer "valid_record_count", default: 0, null: false
    t.integer "issue_count", default: 0, null: false
    t.integer "blocking_issue_count", default: 0, null: false
    t.integer "create_count", default: 0, null: false
    t.integer "update_count", default: 0, null: false
    t.integer "skip_count", default: 0, null: false
    t.integer "reject_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "created_at"], name: "index_import_runs_on_company_id_and_created_at"
    t.index ["company_id"], name: "index_import_runs_on_company_id"
    t.index ["status"], name: "index_import_runs_on_status"
  end

  add_foreign_key "audit_events", "import_runs"
  add_foreign_key "departments", "companies"
  add_foreign_key "employee_contracts", "employees"
  add_foreign_key "employees", "companies"
  add_foreign_key "employees", "departments"
  add_foreign_key "employees", "employees", column: "manager_id"
  add_foreign_key "import_issues", "import_runs"
  add_foreign_key "import_runs", "companies"
end
