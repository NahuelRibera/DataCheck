require "rails_helper"

RSpec.describe Imports::VerificationService, type: :service do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  def run_full_import(rows)
    write_source_csv(import_run, rows)
    Imports::PreflightService.new(import_run).call
    import_run.reload
    Imports::DryRunService.new(import_run).call
    Imports::ExecuteService.new(import_run).call
    import_run.reload
  end

  it "passes every check for a cleanly migrated dataset" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    checks = Imports::VerificationService.new(import_run).call

    expect(checks).to all(have_attributes(status: "pass"))
  end

  it "detects a broken invariant: an employee linked to another company's department" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    other_company_department = create(:department)
    Employee.find_by(external_id: "EMP-1").update_column(:department_id, other_company_department.id)

    checks = Imports::VerificationService.new(import_run).call
    failing = checks.find { |c| c.name == "no_cross_company_departments" }

    expect(failing.status).to eq("fail")
  end

  it "detects a broken invariant: import_run counters disagree with the normalized file" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    import_run.update_column(:create_count, import_run.create_count + 1) # pretend one extra create happened

    checks = Imports::VerificationService.new(import_run).call
    failing = checks.find { |c| c.name == "counts_reconcile" }

    expect(failing.status).to eq("fail")
  end

  it "detects a broken invariant: a missing start date" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    Employee.find_by(external_id: "EMP-1").update_column(:start_date, nil)

    checks = Imports::VerificationService.new(import_run).call
    failing = checks.find { |c| c.name == "all_employees_have_start_date" }

    expect(failing.status).to eq("fail")
  end

  def verification_check(name)
    Imports::VerificationService.new(import_run).call.find { |c| c.name == name }
  end

  it "detects a broken invariant: an employee reporting to a manager in another company" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    outsider = create(:employee)
    expect(outsider.company_id).not_to eq(company.id)
    Employee.find_by(external_id: "EMP-1").update_column(:manager_id, outsider.id)

    failing = verification_check("no_cross_company_managers")

    expect(failing.status).to eq("fail")
    expect(failing.details).to eq("1 employee(s) reporting to a manager in another company")
  end

  it "detects a broken invariant: a blank required field" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    Employee.find_by(external_id: "EMP-1").update_column(:first_name, "   ")

    failing = verification_check("required_fields_present")

    expect(failing.status).to eq("fail")
    expect(failing.details).to eq("1 employee(s) missing a required field")
  end

  it "detects a broken invariant: an accepted row is absent from the database" do
    run_full_import([
      default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", department_external_id: "DEPT-ENG"),
    ])
    Employee.find_by(external_id: "EMP-2").delete

    failing = verification_check("imported_rows_now_exist")

    expect(failing.status).to eq("fail")
    expect(failing.details).to eq("1 accepted row(s) not found in the database")
  end

  # Duplicates cannot be constructed: the (company_id, external_id) unique
  # index is the final guarantee, so the check passes and the database refuses
  # to create the broken state it guards against.
  it "cannot see duplicate external ids because the unique index prevents them" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    existing = Employee.find_by(external_id: "EMP-1")

    expect {
      duplicate = existing.dup
      duplicate.save!(validate: false)
    }.to raise_error(ActiveRecord::RecordNotUnique)

    check = verification_check("no_duplicate_external_ids")
    expect(check.status).to eq("pass")
    expect(check.details).to eq("0 external_id(s) duplicated within this company")
  end

  it "records a summary audit event" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    Imports::VerificationService.new(import_run).call

    expect(import_run.audit_events.pluck(:event_type)).to include("verification_completed")
  end

  it "records an empty failed_checks list when every check passes" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    Imports::VerificationService.new(import_run).call

    event = import_run.audit_events.find_by!(event_type: "verification_completed")
    expect(event.metadata["failed_checks"]).to eq([])
    expect(event.metadata["failed"]).to eq(0)
  end

  it "records only the names of failed checks in the audit event" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    employee = Employee.find_by(external_id: "EMP-1")
    employee.update_column(:start_date, nil)

    Imports::VerificationService.new(import_run).call

    event = import_run.audit_events.find_by!(event_type: "verification_completed")
    expect(event.metadata["failed_checks"]).to eq(["all_employees_have_start_date"])
    expect(event.metadata["failed"]).to eq(1)
    expect(event.message).to eq("Verification completed: #{event.metadata['passed']} passed, 1 failed.")
    serialized = event.metadata.to_json
    expect(serialized).not_to include(employee.first_name)
    expect(serialized).not_to include(employee.email)
  end
end
