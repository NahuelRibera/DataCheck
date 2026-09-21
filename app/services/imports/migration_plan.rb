require "csv"

module Imports
  # Shared classification + (optionally) persistence logic used by both
  # DryRunService (persist: false) and ExecuteService (persist: true), so
  # the two can never drift into computing different numbers. Reads the
  # normalized CSV produced by the Python preflight profiler.
  #
  # Employees are resolved in two full passes over all eligible rows: first
  # core attributes (so every row -- new or existing -- has a real database
  # id and a hash entry), then manager_id. A manager referenced by an early
  # row may be a row that appears later in the file, so manager resolution
  # can only safely happen once every row has been through pass one.
  class MigrationPlan
    Result = Struct.new(:create_count, :update_count, :skip_count, :reject_count, keyword_init: true)

    def initialize(import_run, persist:)
      @import_run = import_run
      @company = import_run.company
      @persist = persist
    end

    def call
      rows = read_normalized_rows
      eligible_rows = rows.reject { |row| row[:blocked] }
      reject_count = rows.size - eligible_rows.size

      departments_by_code = company.departments.index_by(&:external_id)
      employees_by_external_id = company.employees.includes(:manager).index_by(&:external_id)

      plan_rows = eligible_rows.map { |row| resolve_core(row, departments_by_code, employees_by_external_id) }
      plan_rows.each { |plan_row| resolve_manager(plan_row, employees_by_external_id) }

      create_count = plan_rows.count { |p| p[:is_new] }
      update_count = plan_rows.count { |p| !p[:is_new] && (p[:core_changed] || p[:manager_changed]) }
      skip_count = plan_rows.count { |p| !p[:is_new] && !p[:core_changed] && !p[:manager_changed] }

      Result.new(create_count: create_count, update_count: update_count, skip_count: skip_count, reject_count: reject_count)
    end

    private

    attr_reader :import_run, :company, :persist

    def read_normalized_rows
      CSV.read(import_run.normalized_csv_path, headers: true).map do |row|
        {
          external_id: row["external_id"],
          first_name: row["first_name"],
          last_name: row["last_name"],
          email: row["email"],
          department_external_id: row["department_external_id"],
          manager_external_id: row["manager_external_id"],
          start_date: row["start_date"],
          gross_salary_cents: row["gross_salary_cents"],
          status: row["status"],
          blocked: row["blocked"] == "True",
        }
      end
    end

    def resolve_core(row, departments_by_code, employees_by_external_id)
      existing = employees_by_external_id[row[:external_id]]
      is_new = existing.nil?
      employee = existing || Employee.new(company: company, external_id: row[:external_id])
      previous_manager_external_id = existing&.manager&.external_id

      department = row[:department_external_id].presence && departments_by_code[row[:department_external_id]]

      employee.assign_attributes(
        first_name: row[:first_name],
        last_name: row[:last_name],
        email: row[:email],
        department_id: department&.id,
        start_date: row[:start_date].presence,
        gross_salary_cents: row[:gross_salary_cents].presence,
        status: row[:status]
      )
      core_changed = employee.changed?
      employee.save! if persist

      employees_by_external_id[row[:external_id]] = employee

      {
        row: row,
        employee: employee,
        is_new: is_new,
        core_changed: core_changed,
        previous_manager_external_id: previous_manager_external_id,
        manager_changed: false,
      }
    end

    def resolve_manager(plan_row, employees_by_external_id)
      manager_external_id = plan_row[:row][:manager_external_id].presence
      manager_changed = plan_row[:previous_manager_external_id] != manager_external_id
      plan_row[:manager_changed] = manager_changed
      return unless persist && manager_changed

      manager = manager_external_id && employees_by_external_id[manager_external_id]
      plan_row[:employee].update_column(:manager_id, manager&.id)
    end
  end
end
