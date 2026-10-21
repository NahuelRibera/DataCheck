require "rails_helper"

# Two requests racing on one import run, each on its own database
# connection. Transactional tests would share a single connection (and so
# never contend for the row lock), so this file commits for real and cleans
# up after itself.
RSpec.describe "Concurrent import steps on one run", type: :service do
  self.use_transactional_tests = false

  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  after do
    [EmployeeContract, Employee, AuditEvent, ImportIssue, ImportRun, Department, Company].each(&:delete_all)
  end

  def prepare_dry_run
    write_source_csv(import_run, [
      default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", department_external_id: "DEPT-ENG"),
    ])
    Imports::PreflightService.new(import_run).call
    Imports::DryRunService.new(import_run.reload).call
  end

  # Runs each block in its own thread and connection, released together, and
  # returns what each one raised (nil for success).
  def race(*steps)
    gate = Queue.new
    threads = steps.map do |step|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          step.call
          nil
        rescue StandardError => e
          e
        end
      end
    end
    steps.size.times { gate << :go }
    threads.map(&:value)
  end

  # Slows the migration down so the second request arrives while the first
  # is still inside it.
  def slow_migration
    allow(Imports::MigrationPlan).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      plan = original.call(*args, **kwargs)
      allow(plan).to receive(:call).and_wrap_original do |call|
        sleep 0.3
        call.call
      end
      plan
    end
  end

  it "lets exactly one of two simultaneous executes run" do
    prepare_dry_run
    slow_migration

    outcomes = race(
      -> { Imports::ExecuteService.new(ImportRun.find(import_run.id)).call },
      -> { Imports::ExecuteService.new(ImportRun.find(import_run.id)).call }
    )

    expect(outcomes.compact.map(&:class)).to eq([Imports::StaleStateError])
    reloaded = import_run.reload
    expect(reloaded.status).to eq("completed")
    expect(reloaded.audit_events.where(event_type: "import_started").count).to eq(1)
    expect(reloaded.audit_events.where(event_type: "import_completed").count).to eq(1)
    expect(reloaded.audit_events.where(event_type: "import_failed")).to be_empty
    expect(reloaded.create_count).to eq(2)
    expect(Employee.where(company: company).count).to eq(2)
  end

  it "never lets a dry run overwrite a run that an execute is importing" do
    prepare_dry_run
    slow_migration

    outcomes = race(
      -> { Imports::ExecuteService.new(ImportRun.find(import_run.id)).call },
      lambda {
        sleep 0.1 # let execute claim the run first
        Imports::DryRunService.new(ImportRun.find(import_run.id)).call
      }
    )

    expect(outcomes.map { |o| o&.class }).to eq([nil, Imports::StaleStateError])
    reloaded = import_run.reload
    expect(reloaded.status).to eq("completed")
    expect(reloaded.audit_events.where(event_type: "dry_run_started").count).to eq(1) # only the setup's
  end
end
