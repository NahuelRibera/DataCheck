require "csv"

namespace :demo do
  desc "Regenerate deterministic demo CSVs and seed the database for a clean interview demo"
  task seed: :environment do
    DEMO_COMPANY_EXTERNAL_ID = "ACME-HR".freeze
    DEMO_COMPANY_NAME = "Acme Robotics Inc.".freeze
    DEPARTMENTS = [
      ["DEPT-ENG", "Engineering"],
      ["DEPT-SAL", "Sales"],
      ["DEPT-MKT", "Marketing"],
      ["DEPT-FIN", "Finance"],
      ["DEPT-PPL", "People & HR"],
      ["DEPT-OPS", "Operations"],
      ["DEPT-SUP", "Customer Support"],
      ["DEPT-LEG", "Legal"],
    ].freeze
    PRESEEDED_COUNT = 60
    MUTATED_COUNT = 15

    puts "Generating deterministic demo CSVs..."
    unless system("python3", Rails.root.join("scripts", "generate_demo_data.py").to_s)
      abort "demo:seed aborted: scripts/generate_demo_data.py failed"
    end

    existing = Company.find_by(external_id: DEMO_COMPANY_EXTERNAL_ID)
    if existing
      puts "Removing previous demo company and its data..."
      run_ids = existing.import_runs.pluck(:id)
      # Company#destroy clears self-referential manager_id references before
      # cascading (see Company#clear_employee_manager_references) so this is
      # safe even though employees can manage other employees.
      existing.destroy!
      run_ids.each { |id| FileUtils.rm_rf(Rails.root.join("storage", "import_runs", id.to_s)) }
    end

    company = Company.create!(name: DEMO_COMPANY_NAME, external_id: DEMO_COMPANY_EXTERNAL_ID)
    departments = DEPARTMENTS.map do |external_id, name|
      company.departments.create!(external_id: external_id, name: name)
    end
    departments_by_code = departments.index_by(&:external_id)

    puts "Pre-seeding #{PRESEEDED_COUNT} existing employees (so a clean import demonstrates update/skip)..."
    clean_rows = CSV.read(Rails.root.join("data", "demo", "clean_employees.csv"), headers: true).first(PRESEEDED_COUNT)
    clean_rows.each_with_index do |row, index|
      company.employees.create!(
        external_id: row["external_id"],
        first_name: row["first_name"],
        last_name: row["last_name"],
        email: row["email"],
        department: departments_by_code[row["department_external_id"]],
        start_date: row["start_date"],
        gross_salary_cents: (row["gross_salary"].to_f * 100).round,
        status: row["status"]
      )
    end
    # Mutate a subset in the DATABASE only, so the upcoming clean import has
    # something real to update (managers are intentionally left unresolved
    # here -- the import run will resolve and set them).
    company.employees.order(:external_id).limit(MUTATED_COUNT).each do |employee|
      employee.update!(first_name: "#{employee.first_name}-Legacy", gross_salary_cents: employee.gross_salary_cents - 500)
    end

    puts "Seeding contract history (backs the payroll export incident case study)..."
    company.employees.order(:external_id).each_with_index do |employee, index|
      EmployeeContract.create!(
        employee: employee, start_date: employee.start_date || Date.new(2022, 1, 1),
        salary_cents: employee.gross_salary_cents, contract_type: "permanent"
      )
      # Give the first few employees a second, more recent contract so
      # Payroll::ExportQuery has a real "which one is current" case to solve.
      next unless index < 5

      EmployeeContract.create!(
        employee: employee, start_date: Date.current - 30, salary_cents: employee.gross_salary_cents + 25_000,
        contract_type: "permanent"
      )
    end

    puts "Creating historical import runs for dashboard flavor..."
    older_completed = company.import_runs.create!(
      filename: "q1_batch_import.csv", status: "completed", source_record_count: 40, valid_record_count: 40,
      create_count: 40, update_count: 0, skip_count: 0, reject_count: 0,
      started_at: 6.days.ago, completed_at: 6.days.ago, created_at: 6.days.ago
    )
    older_completed.log_event!("import_uploaded", "File q1_batch_import.csv uploaded.")
    older_completed.log_event!("import_completed", "Migration completed: created=40.")

    older_blocked = company.import_runs.create!(
      filename: "legacy_export_attempt_1.csv", status: "blocked", source_record_count: 55, valid_record_count: 48,
      issue_count: 9, blocking_issue_count: 7, created_at: 3.days.ago
    )
    older_blocked.log_event!("import_uploaded", "File legacy_export_attempt_1.csv uploaded.")
    older_blocked.log_event!("issues_detected", "9 issue(s) detected (7 blocking, 2 warning).")

    puts "Creating the two live demo import runs (bad + clean)..."
    bad_run = company.import_runs.create!(filename: "bad_employees.csv", status: "uploaded")
    bad_run.save_source_csv!(File.open(Rails.root.join("data", "demo", "bad_employees.csv")))
    bad_run.log_event!("import_uploaded", "File bad_employees.csv uploaded.")

    clean_run = company.import_runs.create!(filename: "clean_employees.csv", status: "uploaded")
    clean_run.save_source_csv!(File.open(Rails.root.join("data", "demo", "clean_employees.csv")))
    clean_run.log_event!("import_uploaded", "File clean_employees.csv uploaded.")

    puts "Done."
    puts "  Company:        #{company.name} (#{company.external_id})"
    puts "  Departments:    #{departments.size}"
    puts "  Employees:      #{company.employees.count} (pre-existing, for update/skip demo)"
    puts "  Bad run:        ##{bad_run.id} (data/demo/bad_employees.csv, not yet profiled)"
    puts "  Clean run:      ##{clean_run.id} (data/demo/clean_employees.csv, not yet profiled)"
  end
end
