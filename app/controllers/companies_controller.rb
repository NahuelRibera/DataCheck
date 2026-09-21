class CompaniesController < ApplicationController
  def index
    @companies = Company.order(:name)
    @employee_counts = Employee.group(:company_id).count
  end

  def show
    @company = Company.find(params[:id])
    @department_count = @company.departments.count
    @employee_count = @company.employees.count
    # includes(:company) even though it's always this one company -- the
    # import_runs/_table partial is shared with the dashboard's cross-company
    # listing and calls run.company.name per row.
    @import_runs = @company.import_runs.includes(:company).recent_first.limit(10)
  end
end
