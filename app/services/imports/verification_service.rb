require "csv"

module Imports
  # Post-import integrity checks computed from actual database state, not
  # from in-memory bookkeeping. Every check here is deliberately something
  # that COULD fail -- foreign keys alone don't guarantee an employee's
  # department or manager belongs to the same company, for example.
  class VerificationService
    Check = Struct.new(:name, :status, :details, keyword_init: true)

    def initialize(import_run)
      @import_run = import_run
      @company = import_run.company
    end

    def call
      checks = [
        check_counts_reconcile,
        check_required_fields_present,
        check_no_cross_company_departments,
        check_no_cross_company_managers,
        check_all_employees_have_start_date,
        check_no_duplicate_external_ids,
        check_imported_rows_now_exist,
      ]

      passed = checks.count { |c| c.status == "pass" }
      failed = checks.count { |c| c.status == "fail" }

      import_run.update!(metadata: import_run.metadata.merge("verification" => checks.map(&:to_h).map(&:stringify_keys)))
      import_run.log_event!(
        "verification_completed",
        "Verification completed: #{passed} passed, #{failed} failed.",
        metadata: { passed: passed, failed: failed }
      )

      checks
    end

    private

    attr_reader :import_run, :company

    # Reconciles ImportRun's own counters against a fresh read of the
    # normalized CSV: every accepted (non-blocked) row should be exactly
    # one create/update/skip, and every blocked row exactly one reject.
    # This catches the class of bug where dry run and execute silently
    # disagree, or where a counter update was missed.
    def check_counts_reconcile
      unless File.exist?(import_run.normalized_csv_path)
        return build_check("counts_reconcile", true, "no normalized file to reconcile against")
      end

      rows = CSV.read(import_run.normalized_csv_path, headers: true)
      accepted_count = rows.count { |row| row["blocked"] != "True" }
      blocked_count = rows.size - accepted_count

      recorded_accepted = import_run.create_count + import_run.update_count + import_run.skip_count
      accepted_match = recorded_accepted == accepted_count
      reject_match = import_run.reject_count == blocked_count

      details = "recorded accepted (create+update+skip)=#{recorded_accepted} vs normalized accepted=#{accepted_count}; " \
                "recorded reject=#{import_run.reject_count} vs normalized blocked=#{blocked_count}"
      build_check("counts_reconcile", accepted_match && reject_match, details)
    end

    def check_required_fields_present
      bad = company.employees.where(
        "trim(coalesce(first_name, '')) = '' OR trim(coalesce(last_name, '')) = '' OR trim(coalesce(external_id, '')) = ''"
      ).count
      build_check("required_fields_present", bad.zero?, "#{bad} employee(s) missing a required field")
    end

    def check_no_cross_company_departments
      bad = company.employees.joins(:department)
                    .where.not(departments: { company_id: company.id })
                    .count
      build_check("no_cross_company_departments", bad.zero?, "#{bad} employee(s) linked to another company's department")
    end

    def check_no_cross_company_managers
      bad = Employee.joins("INNER JOIN employees managers ON managers.id = employees.manager_id")
                     .where(company_id: company.id)
                     .where.not("managers.company_id = employees.company_id")
                     .count
      build_check("no_cross_company_managers", bad.zero?, "#{bad} employee(s) reporting to a manager in another company")
    end

    def check_all_employees_have_start_date
      bad = company.employees.where(start_date: nil).count
      build_check("all_employees_have_start_date", bad.zero?, "#{bad} employee(s) missing a start date")
    end

    def check_no_duplicate_external_ids
      bad = company.employees.group(:external_id).having("count(*) > 1").count.size
      build_check("no_duplicate_external_ids", bad.zero?, "#{bad} external_id(s) duplicated within this company")
    end

    def check_imported_rows_now_exist
      return build_check("imported_rows_now_exist", true, "no normalized file to verify against") unless File.exist?(import_run.normalized_csv_path)

      accepted_external_ids = CSV.read(import_run.normalized_csv_path, headers: true)
                                  .reject { |row| row["blocked"] == "True" }
                                  .map { |row| row["external_id"] }
      present_external_ids = company.employees.where(external_id: accepted_external_ids).pluck(:external_id).to_set
      missing = accepted_external_ids.count { |external_id| !present_external_ids.include?(external_id) }
      build_check("imported_rows_now_exist", missing.zero?, "#{missing} accepted row(s) not found in the database")
    end

    def build_check(name, passed, details)
      Check.new(name: name, status: passed ? "pass" : "fail", details: details)
    end
  end
end
