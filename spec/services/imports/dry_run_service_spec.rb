require "rails_helper"

RSpec.describe Imports::DryRunService, type: :service do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  def run_preflight(rows)
    write_source_csv(import_run, rows)
    Imports::PreflightService.new(import_run).call
    import_run.reload
  end

  it "computes create counts for brand new employees without writing to the employees table" do
    run_preflight([
      default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", department_external_id: "DEPT-ENG"),
    ])

    expect { Imports::DryRunService.new(import_run).call }.not_to change { Employee.count }

    import_run.reload
    expect(import_run.create_count).to eq(2)
    expect(import_run.update_count).to eq(0)
    expect(import_run.skip_count).to eq(0)
    expect(import_run.status).to eq("dry_run_completed")
  end

  it "computes update counts when an existing employee's data changed" do
    create(:employee, company: company, department: department, external_id: "EMP-1", first_name: "Old")
    run_preflight([default_employee_row(external_id: "EMP-1", first_name: "New", department_external_id: "DEPT-ENG")])

    Imports::DryRunService.new(import_run).call
    import_run.reload

    expect(import_run.update_count).to eq(1)
    expect(import_run.create_count).to eq(0)
    expect(Employee.find_by(external_id: "EMP-1").first_name).to eq("Old") # unchanged by dry run
  end

  it "computes skip counts when an existing employee's data is identical" do
    create(:employee, company: company, department: department, external_id: "EMP-1", first_name: "Ada",
                       last_name: "Lovelace", email: "ada@example.com", start_date: Date.new(2024, 1, 1),
                       gross_salary_cents: 5_000_000, status: "active")
    run_preflight([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])

    Imports::DryRunService.new(import_run).call
    import_run.reload

    expect(import_run.skip_count).to eq(1)
    expect(import_run.update_count).to eq(0)
  end

  it "counts blocked rows as rejects and leaves the employees table untouched" do
    run_preflight([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-GHOST")])

    expect { Imports::DryRunService.new(import_run).call }.not_to change { Employee.count }

    import_run.reload
    expect(import_run.reject_count).to eq(1)
    expect(import_run.create_count).to eq(0)
  end

  it "marks the run failed with an audit trail if called before preflight ever ran" do
    fresh_run = create(:import_run, company: company)

    expect { Imports::DryRunService.new(fresh_run).call }.to raise_error(Errno::ENOENT)

    reloaded = fresh_run.reload
    expect(reloaded.status).to eq("failed")
    expect(reloaded.audit_events.pluck(:event_type)).to include("import_failed")
  end
end
