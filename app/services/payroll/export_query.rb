module Payroll
  # Returns exactly one row per employee: their CURRENT contract (the one
  # with the latest start_date).
  #
  # A naive `employees JOIN employee_contracts` returns one row per
  # CONTRACT, which silently duplicates any employee who has been
  # re-contracted (a raise, a promotion, a renewal). See
  # docs/incident-case-study.md for the incident this fixes and
  # spec/services/payroll/export_query_spec.rb for the regression test that
  # reproduces the original bug and proves this query avoids it.
  #
  # Postgres's DISTINCT ON does this in one query without pulling every
  # historical contract into Ruby to pick the latest one there.
  class ExportQuery
    def self.call(company)
      latest_contract_ids =
        EmployeeContract
          .where(employee_id: company.employees.select(:id))
          .select("DISTINCT ON (employee_id) id")
          .order(:employee_id, start_date: :desc)

      EmployeeContract.where(id: latest_contract_ids).includes(:employee).order(:employee_id)
    end
  end
end
