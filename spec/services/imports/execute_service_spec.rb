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

  describe "row lock and status re-check" do
    def prepare_dry_run
      run_preflight([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
      Imports::DryRunService.new(import_run).call
      import_run.reload
    end

    it "refuses a second execute on a completed run and keeps one import_started event" do
      prepare_dry_run
      Imports::ExecuteService.new(import_run).call

      expect { Imports::ExecuteService.new(import_run).call }.to raise_error(Imports::StaleStateError)

      reloaded = import_run.reload
      expect(reloaded.status).to eq("completed")
      expect(reloaded.audit_events.where(event_type: "import_started").count).to eq(1)
      expect(reloaded.audit_events.pluck(:event_type)).not_to include("import_failed")
      expect(Employee.where(company: company).count).to eq(1)
    end

    it "refuses a run another request already moved to importing" do
      prepare_dry_run
      stale = ImportRun.find(import_run.id)
      ImportRun.where(id: import_run.id).update_all(status: "importing")

      expect { Imports::ExecuteService.new(stale).call }.to raise_error(Imports::StaleStateError)

      reloaded = import_run.reload
      expect(reloaded.status).to eq("importing") # not relabeled "failed"
      expect(reloaded.audit_events.pluck(:event_type)).not_to include("import_started", "import_failed")
      expect(Employee.count).to eq(0)
    end

    it "refuses while preflight is profiling the run" do
      prepare_dry_run
      stale = ImportRun.find(import_run.id)
      ImportRun.where(id: import_run.id).update_all(status: "profiling")

      expect { Imports::ExecuteService.new(stale).call }.to raise_error(Imports::StaleStateError)
      expect(Employee.count).to eq(0)
    end

    # Regression for the first DC-GEN-015 attempt: ImportRun#with_lock calls
    # lock!, which raises a RuntimeError on a record with unpersisted
    # changes. The service must read the locked row, not trust the caller's
    # in-memory copy.
    it "decides from the locked row even when the caller's copy has unsaved changes" do
      prepare_dry_run
      Imports::ExecuteService.new(import_run).call
      stale = ImportRun.find(import_run.id)
      stale.status = "dry_run_completed"

      expect { Imports::ExecuteService.new(stale).call }.to raise_error(Imports::StaleStateError)

      expect(import_run.reload.audit_events.where(event_type: "import_started").count).to eq(1)
    end

    # Regression for the second DC-GEN-015 attempt: the blocked check moved
    # inside the lock's transaction and raised there, which rolled back the
    # execution_blocked audit event it had just written.
    it "persists execution_blocked when the locked row turns out to be blocked" do
      prepare_dry_run
      stale = ImportRun.find(import_run.id)
      ImportRun.where(id: import_run.id).update_all(blocking_issue_count: 1)

      expect { Imports::ExecuteService.new(stale).call }.to raise_error(Imports::ExecuteService::ExecutionBlockedError)

      reloaded = import_run.reload
      expect(reloaded.audit_events.pluck(:event_type)).to include("execution_blocked")
      expect(reloaded.audit_events.pluck(:event_type)).not_to include("import_started", "import_failed")
      expect(reloaded.status).to eq("dry_run_completed")
      expect(Employee.count).to eq(0)
    end
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

  it "keeps exception text (fake email/salary) out of the import_failed audit event and the log" do
    run_preflight([default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    secret = "jane.doe@example.invalid salary=987654"
    plan = instance_double(Imports::MigrationPlan)
    allow(Imports::MigrationPlan).to receive(:new).and_return(plan)
    allow(plan).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "PG::Error: key (email)=(#{secret})")

    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    begin
      expect { Imports::ExecuteService.new(import_run).call }.to raise_error(ActiveRecord::StatementInvalid)
    ensure
      Rails.logger = original_logger
    end

    reloaded = import_run.reload
    expect(reloaded.status).to eq("failed")
    event = reloaded.audit_events.find_by!(event_type: "import_failed")
    expect(event.metadata["error_class"]).to eq("ActiveRecord::StatementInvalid")
    serialized = [event.message, event.metadata.to_json].join(" ")
    ["jane.doe", "example.invalid", "987654", "PG::Error"].each do |fragment|
      expect(serialized).not_to include(fragment)
      expect(log.string).not_to include(fragment)
    end
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
