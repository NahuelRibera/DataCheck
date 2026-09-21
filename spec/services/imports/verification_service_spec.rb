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

  it "records a summary audit event" do
    run_full_import([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    Imports::VerificationService.new(import_run).call

    expect(import_run.audit_events.pluck(:event_type)).to include("verification_completed")
  end
end
