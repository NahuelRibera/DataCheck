require "rails_helper"

RSpec.describe Imports::PreflightService, type: :service do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  it "detects a duplicate external_id as a blocking issue" do
    write_source_csv(import_run, [
      default_employee_row(department_external_id: "DEPT-ENG"),
      default_employee_row(department_external_id: "DEPT-ENG", first_name: "Duplicate"),
    ])

    expect(Imports::PreflightService.new(import_run).call).to be true

    import_run.reload
    expect(import_run.status).to eq("blocked")
    expect(import_run.blocking_issue_count).to eq(2)
    expect(import_run.import_issues.pluck(:issue_type)).to all(eq("duplicate_external_id"))
  end

  it "detects an orphan manager as a blocking issue" do
    write_source_csv(import_run, [
      default_employee_row(department_external_id: "DEPT-ENG", manager_external_id: "EMP-DOES-NOT-EXIST"),
    ])

    Imports::PreflightService.new(import_run).call
    import_run.reload

    expect(import_run.import_issues.pluck(:issue_type)).to eq(["orphan_manager"])
    expect(import_run.blocked?).to be true
  end

  it "detects an unknown department as a blocking issue" do
    write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-GHOST")])

    Imports::PreflightService.new(import_run).call
    import_run.reload

    expect(import_run.import_issues.pluck(:issue_type)).to eq(["unknown_department"])
  end

  it "normalizes an alternate salary format without raising an issue" do
    write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG", gross_salary: "32,500.50")])

    Imports::PreflightService.new(import_run).call
    import_run.reload

    expect(import_run.import_issues).to be_empty
    expect(import_run.status).to eq("ready")

    normalized = CSV.read(import_run.normalized_csv_path, headers: true)
    expect(normalized.first["gross_salary_cents"]).to eq("3250050")
  end

  it "marks the run ready with zero blocking issues for a fully clean file" do
    write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG")])

    Imports::PreflightService.new(import_run).call
    import_run.reload

    expect(import_run.status).to eq("ready")
    expect(import_run.blocking_issue_count).to eq(0)
    expect(import_run.valid_record_count).to eq(1)
  end

  it "writes a chronological audit trail" do
    write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG")])

    Imports::PreflightService.new(import_run).call

    event_types = import_run.audit_events.chronological.pluck(:event_type)
    expect(event_types).to eq(%w[preflight_started safe_normalization_completed preflight_completed])
  end

  it "fails the run cleanly when the CSV file is missing" do
    import_run.update!(status: "uploaded")
    # No source CSV written -- simulates a corrupted/missing upload.
    result = Imports::PreflightService.new(import_run).call

    expect(result).to be false
    expect(import_run.reload.status).to eq("failed")
    expect(import_run.audit_events.pluck(:event_type)).to include("import_failed")
  end
end
