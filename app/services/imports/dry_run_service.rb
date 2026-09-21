module Imports
  # Computes what an execution WOULD do -- create/update/skip/reject counts
  # -- without writing anything to the employees table. Shares its
  # classification logic with ExecuteService via MigrationPlan so the two
  # can never disagree.
  class DryRunService
    def initialize(import_run)
      @import_run = import_run
    end

    def call
      import_run.log_event!("dry_run_started", "Dry run started.")

      result = MigrationPlan.new(import_run, persist: false).call

      import_run.update!(
        status: "dry_run_completed",
        create_count: result.create_count,
        update_count: result.update_count,
        skip_count: result.skip_count,
        reject_count: result.reject_count
      )

      import_run.log_event!(
        "dry_run_completed",
        "Dry run computed create=#{result.create_count} update=#{result.update_count} " \
        "skip=#{result.skip_count} reject=#{result.reject_count}.",
        metadata: result.to_h
      )

      result
    rescue StandardError => e
      # Same reasoning as ExecuteService: the UI/API already guard against
      # calling this before preflight has produced a normalized CSV, but a
      # direct caller (console, future code path) shouldn't be met with an
      # unhandled exception and no audit trail explaining what happened.
      import_run.update!(status: "failed")
      import_run.log_event!("import_failed", "Dry run failed: #{e.message.truncate(300)}")
      raise
    end

    private

    attr_reader :import_run
  end
end
