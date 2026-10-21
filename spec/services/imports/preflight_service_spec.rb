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
  %w[profiling importing].each do |busy_status|
    it "refuses a run that is #{busy_status} without logging or changing it" do
      write_source_csv(import_run, [default_employee_row])
      stale = ImportRun.find(import_run.id)
      ImportRun.where(id: import_run.id).update_all(status: busy_status)

      expect { Imports::PreflightService.new(stale).call }.to raise_error(Imports::StaleStateError)

      reloaded = import_run.reload
      expect(reloaded.status).to eq(busy_status)
      expect(reloaded.audit_events).to be_empty
    end
  end

  # "profiling" now refuses every other step, so an unexpected exception
  # must not leave the run stuck in it.
  it "marks the run failed, not stuck in profiling, when profiling raises" do
    write_source_csv(import_run, [default_employee_row])
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "python3")

    expect { Imports::PreflightService.new(import_run).call }.to raise_error(Errno::ENOENT)

    reloaded = import_run.reload
    expect(reloaded.status).to eq("failed")
    event = reloaded.audit_events.find_by!(event_type: "import_failed")
    expect(event.metadata["error_class"]).to eq("Errno::ENOENT")
  end

  # A process that dies mid-step (a deploy, a killed worker) leaves its status behind; the migration's
  # own transaction has rolled back. Preflight was always the way to start over, and must stay so.
  %w[profiling importing].each do |stuck_status|
    it "restarts a run left #{stuck_status} by a step that died over an hour ago" do
      write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG")])
      ImportRun.where(id: import_run.id).update_all(status: stuck_status, updated_at: 2.hours.ago)

      expect(Imports::PreflightService.new(ImportRun.find(import_run.id)).call).to be(true)

      reloaded = import_run.reload
      expect(reloaded.status).to eq("ready")
      started = reloaded.audit_events.find_by!(event_type: "preflight_started")
      expect(started.metadata).to eq("recovered_from" => stuck_status)
    end

    it "still refuses a run that is #{stuck_status} right now" do
      write_source_csv(import_run, [default_employee_row])
      ImportRun.where(id: import_run.id).update_all(status: stuck_status, updated_at: 59.minutes.ago)

      expect { Imports::PreflightService.new(ImportRun.find(import_run.id)).call }.to raise_error(Imports::StaleStateError)
    end
  end

  it "keeps dry run and execute refusing a stale in-progress run: only preflight starts over" do
    write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG")])
    ImportRun.where(id: import_run.id).update_all(status: "importing", updated_at: 2.hours.ago)

    expect { Imports::DryRunService.new(ImportRun.find(import_run.id)).call }.to raise_error(Imports::StaleStateError)
    expect { Imports::ExecuteService.new(ImportRun.find(import_run.id)).call }.to raise_error(Imports::StaleStateError)
  end
end
