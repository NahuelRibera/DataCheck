require "rails_helper"

# Regression coverage for the incident documented in
# docs/incident-case-study.md: a payroll export that joined employees to
# their contract history returned one row per CONTRACT, not per employee,
# so anyone who had been re-contracted showed up twice (or more) in the
# export CSV finance actually opened.
RSpec.describe Payroll::ExportQuery, type: :service do
  let(:company) { create(:company) }

  it "reproduces the original bug: a naive join duplicates employees with multiple contracts" do
    employee = create(:employee, company: company)
    create(:employee_contract, employee: employee, start_date: Date.new(2022, 1, 1), salary_cents: 4_000_000)
    create(:employee_contract, employee: employee, start_date: Date.new(2024, 1, 1), salary_cents: 5_500_000)

    naive_join_row_count = Employee.joins(:employee_contracts).where(company: company).count

    expect(naive_join_row_count).to eq(2) # this is the bug: one employee, two rows
  end

  it "returns exactly one row per employee, even when they have multiple contracts" do
    employee = create(:employee, company: company)
    create(:employee_contract, employee: employee, start_date: Date.new(2022, 1, 1), salary_cents: 4_000_000)
    create(:employee_contract, employee: employee, start_date: Date.new(2024, 1, 1), salary_cents: 5_500_000)

    other_employee = create(:employee, company: company)
    create(:employee_contract, employee: other_employee, start_date: Date.new(2023, 6, 1), salary_cents: 4_800_000)

    rows = Payroll::ExportQuery.call(company).to_a

    expect(rows.map(&:employee_id)).to contain_exactly(employee.id, other_employee.id)
  end

  it "picks the contract with the latest start_date as the current one" do
    employee = create(:employee, company: company)
    create(:employee_contract, employee: employee, start_date: Date.new(2022, 1, 1), salary_cents: 4_000_000)
    latest = create(:employee_contract, employee: employee, start_date: Date.new(2024, 1, 1), salary_cents: 5_500_000)

    row = Payroll::ExportQuery.call(company).find { |r| r.employee_id == employee.id }

    expect(row.id).to eq(latest.id)
    expect(row.salary_cents).to eq(5_500_000)
  end

  it "does not include another company's employees" do
    other_company_employee = create(:employee)
    create(:employee_contract, employee: other_company_employee)

    rows = Payroll::ExportQuery.call(company).to_a

    expect(rows).to be_empty
  end
end
