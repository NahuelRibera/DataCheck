require "rails_helper"

RSpec.describe Imports::VerificationService, ".stored_or_call" do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  def run_full_import
    write_source_csv(import_run, [default_employee_row(external_id: "EMP-1", department_external_id: "DEPT-ENG")])
    Imports::PreflightService.new(import_run).call
    Imports::DryRunService.new(import_run.reload).call
    Imports::ExecuteService.new(import_run).call
    Imports::VerificationService.new(import_run).call
    import_run.reload
  end

  def verification_events
    import_run.audit_events.where(event_type: "verification_completed").count
  end

  it "returns the stored checks as Check structs without writing anything" do
    run_full_import
    events = import_run.audit_events.count

    checks = Imports::VerificationService.stored_or_call(ImportRun.find(import_run.id))

    expect(checks).to all(be_a(Imports::VerificationService::Check))
    expect(checks.map(&:to_h).map(&:stringify_keys)).to eq(import_run.metadata["verification"])
    expect(import_run.audit_events.count).to eq(events)
  end

  it "ignores unexpected keys in a stored check instead of failing" do
    run_full_import
    stored = import_run.metadata["verification"].map { |check| check.merge("extra" => "x") }
    import_run.update_columns(metadata: { "verification" => stored })

    checks = Imports::VerificationService.stored_or_call(ImportRun.find(import_run.id))

    expect(checks.map(&:to_h).map(&:keys)).to all(eq(%i[name status details]))
  end

  context "with two first reads racing on separate connections" do
    self.use_transactional_tests = false

    after do
      [EmployeeContract, Employee, AuditEvent, ImportIssue, ImportRun, Department, Company].each(&:delete_all)
    end

    it "computes and stores the result exactly once" do
      run_full_import
      import_run.update_columns(metadata: import_run.metadata.except("verification"))
      events = verification_events
      allow_any_instance_of(Imports::VerificationService).to receive(:call).and_wrap_original do |original|
        sleep 0.2 # keep the first computation open while the second read arrives
        original.call
      end

      gate = Queue.new
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            Imports::VerificationService.stored_or_call(ImportRun.find(import_run.id)).map(&:to_h)
          end
        end
      end
      2.times { gate << :go }
      results = threads.map(&:value)

      expect(results.uniq.size).to eq(1)
      expect(verification_events).to eq(events + 1)
    end
  end
end
