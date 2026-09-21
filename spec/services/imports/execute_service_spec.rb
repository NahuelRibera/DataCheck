require "rails_helper"

RSpec.describe Imports::ExecuteService, type: :service do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  def run_preflight(rows)
    write_source_csv(import_run, rows)
    Imports::PreflightService.new(import_run).call
    import_run.reload
  end

  it "creates employees transactionally, resolving forward manager references" do
    run_preflight([
      default_employee_row(external_id: "EMP-1", first_name: "Boss", manager_external_id: "", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", first_name: "Report", manager_external_id: "EMP-1", department_external_id: "DEPT-ENG"),
    ])
    Imports::DryRunService.new(import_run).call

    result = Imports::ExecuteService.new(import_run).call

    expect(result.create_count).to eq(2)
    report = Employee.find_by(external_id: "EMP-2")
    expect(report.manager.external_id).to eq("EMP-1")
    expect(import_run.reload.status).to eq("completed")
  end

  it "refuses to execute while blocking issues remain" do
    run_preflight([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-GHOST")])

    expect do
      expect { Imports::ExecuteService.new(import_run).call }
        .to raise_error(Imports::ExecuteService::ExecutionBlockedError)
    end.not_to change { Employee.count }

    reloaded = import_run.reload
    expect(reloaded.audit_events.pluck(:event_type)).to include("execution_blocked")
    expect(reloaded.audit_events.pluck(:event_type)).not_to include("import_failed") # a refusal isn't a crash
    expect(reloaded.status).to eq("blocked") # not relabeled "failed"
  end

  it "marks the run failed (not stuck in 'importing') if execute is called before preflight ever ran" do
    # ExecutionBlockedError only fires for a positive blocking_issue_count;
    # a freshly-created run has none, so nothing but this catches an
    # execute call that skipped preflight/dry run entirely -- there is no
    # normalized.csv yet. The UI/API already guard against this via
    # ready_for_execution?; this proves the service is safe even without
    # that guard, e.g. called directly from a console.
    fresh_run = create(:import_run, company: company)

    expect { Imports::ExecuteService.new(fresh_run).call }.to raise_error(Errno::ENOENT)

    reloaded = fresh_run.reload
    expect(reloaded.status).to eq("failed")
    expect(reloaded.audit_events.pluck(:event_type)).to include("import_failed")
  end

  it "is idempotent: running the same clean import twice creates zero duplicates" do
    rows = [
      default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", department_external_id: "DEPT-ENG"),
    ]

    run_preflight(rows)
    Imports::DryRunService.new(import_run).call
    Imports::ExecuteService.new(import_run).call
    expect(Employee.where(company: company).count).to eq(2)

    second_run = create(:import_run, company: company)
    write_source_csv(second_run, rows)
    Imports::PreflightService.new(second_run).call
    second_run.reload
    result = Imports::DryRunService.new(second_run).call
    Imports::ExecuteService.new(second_run).call

    expect(result.create_count).to eq(0)
    expect(result.skip_count).to eq(2)
    expect(Employee.where(company: company).count).to eq(2)
  end

  it "rolls back all changes if execution fails partway through" do
    run_preflight([
      default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", department_external_id: "DEPT-ENG"),
    ])
    Imports::DryRunService.new(import_run).call

    allow_any_instance_of(Employee).to receive(:save!) do |instance|
      raise ActiveRecord::RecordInvalid, instance if instance.external_id == "EMP-2"

      instance.save(validate: false)
    end

    expect { Imports::ExecuteService.new(import_run).call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Employee.where(company: company).count).to eq(0)
    expect(import_run.reload.status).to eq("failed")
  end

  it "enforces uniqueness at the database level as a final guarantee" do
    create(:employee, company: company, external_id: "EMP-1")
    expect do
      build(:employee, company: company, external_id: "EMP-1").save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
