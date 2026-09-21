require "open3"
require "json"
require "tempfile"

module Imports
  # Invokes the Python preflight profiler (scripts/profile_import.py) as a
  # subprocess, persists the ImportIssue records it finds, and moves the
  # ImportRun into "blocked" or "ready". Never shells out with interpolated
  # user input -- arguments are passed as an argv array to Open3, never
  # through a constructed shell string.
  class PreflightService
    PYTHON_BIN = ENV.fetch("PYTHON_BIN", "python3")
    SCRIPT_PATH = Rails.root.join("scripts", "profile_import.py")

    def initialize(import_run)
      @import_run = import_run
      @company = import_run.company
    end

    def call
      import_run.update!(status: "profiling")
      import_run.log_event!("preflight_started", "Preflight profiling started.")

      known_departments_file = write_temp_list(company.departments.pluck(:external_id))
      known_employees_file = write_temp_list(company.employees.pluck(:external_id))

      stdout, stderr, status = Open3.capture3(
        PYTHON_BIN, SCRIPT_PATH.to_s,
        "--csv", import_run.source_csv_path.to_s,
        "--known-departments-file", known_departments_file.path,
        "--known-employees-file", known_employees_file.path,
        "--normalized-output", import_run.normalized_csv_path.to_s
      )

      unless status.success?
        return fail_run!("Preflight profiler exited with status #{status.exitstatus}", stderr)
      end

      result = begin
        JSON.parse(stdout)
      rescue JSON::ParserError
        return fail_run!("Preflight profiler returned malformed JSON output", stderr)
      end

      if result["error"].present?
        return fail_run!("Preflight profiler reported an error: #{result['error']}", stderr)
      end

      persist_result(result)
      true
    ensure
      known_departments_file&.close!
      known_employees_file&.close!
    end

    private

    attr_reader :import_run, :company

    def write_temp_list(values)
      file = Tempfile.new("datacheck-ids")
      file.write(values.join("\n"))
      file.flush
      file
    end

    def persist_result(result)
      import_run.import_issues.delete_all

      issue_rows = result.fetch("issues", []).map do |issue|
        {
          import_run_id: import_run.id,
          row_number: issue["row_number"],
          external_id: issue["external_id"],
          issue_type: issue["issue_type"],
          severity: issue["severity"],
          field_name: issue["field"],
          message: issue["message"],
          metadata: {},
          created_at: Time.current,
          updated_at: Time.current,
        }
      end
      ImportIssue.insert_all(issue_rows) if issue_rows.any?

      blocking_count = result["blocking_count"].to_i
      warning_count = result["warning_count"].to_i

      import_run.update!(
        source_record_count: result["source_count"].to_i,
        valid_record_count: result["valid_count"].to_i,
        issue_count: blocking_count + warning_count,
        blocking_issue_count: blocking_count,
        status: blocking_count.positive? ? "blocked" : "ready"
      )

      if issue_rows.any?
        import_run.log_event!(
          "issues_detected",
          "#{issue_rows.size} issue(s) detected (#{blocking_count} blocking, #{warning_count} warning).",
          metadata: { blocking_count: blocking_count, warning_count: warning_count }
        )
      else
        import_run.log_event!("safe_normalization_completed", "No issues detected; all rows are import-ready.")
      end

      import_run.log_event!(
        "preflight_completed",
        "Preflight completed: #{import_run.status}.",
        metadata: {
          source_count: import_run.source_record_count,
          valid_count: import_run.valid_record_count,
          blocking_count: blocking_count,
          warning_count: warning_count,
        }
      )
    end

    def fail_run!(message, stderr)
      Rails.logger.error("[Imports::PreflightService] #{message} stderr=#{stderr.to_s.truncate(500)}")
      import_run.update!(status: "failed")
      import_run.log_event!("import_failed", message)
      false
    end
  end
end
