module Imports
  # Executes the migration for real, inside a single database transaction.
  # Refuses outright if the run still has blocking issues -- this is the
  # last line of defense above the UI/controller layer, not the only one.
  class ExecuteService
    class ExecutionBlockedError < StandardError; end

    def initialize(import_run)
      @import_run = import_run
    end

    def call
      if import_run.blocked?
        import_run.log_event!(
          "execution_blocked",
          "Execution refused: #{import_run.blocking_issue_count} blocking issue(s) remain."
        )
        raise ExecutionBlockedError, "cannot execute while blocking issues remain"
      end

      import_run.update!(status: "importing", started_at: Time.current)
      import_run.log_event!("import_started", "Migration execution started.")

      result = nil
      ActiveRecord::Base.transaction do
        result = MigrationPlan.new(import_run, persist: true).call
      end

      import_run.update!(
        status: "completed",
        completed_at: Time.current,
        create_count: result.create_count,
        update_count: result.update_count,
        skip_count: result.skip_count,
        reject_count: result.reject_count
      )

      import_run.log_event!(
        "import_completed",
        "Migration completed: created=#{result.create_count} updated=#{result.update_count} " \
        "skipped=#{result.skip_count} rejected=#{result.reject_count}.",
        metadata: result.to_h
      )

      result
    rescue ExecutionBlockedError
      # Already logged as "execution_blocked" above; a refusal is not a
      # crash, so it must not fall into the StandardError handler below and
      # get relabeled "failed" (or double-logged).
      raise
    rescue StandardError => e
      # Broad on purpose: ANY other failure here -- a rolled-back
      # validation, a missing normalized CSV because preflight never ran,
      # an unexpected I/O error -- must leave the run in "failed" with an
      # audit trail entry, never stuck in "importing" with an unhandled
      # exception. The UI/API already guard against calling this without a
      # prior dry run; this is the backstop for callers that skip them
      # (a console, a future code path). The transaction above already
      # rolled back any partial employee writes; this only updates
      # ImportRun's own status.
      import_run.update!(status: "failed")
      import_run.log_event!("import_failed", "Migration execution failed and was rolled back: #{e.message.truncate(300)}")
      raise
    end

    private

    attr_reader :import_run
  end
end
