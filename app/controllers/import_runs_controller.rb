class ImportRunsController < ApplicationController
  before_action :set_import_run, only: [:show, :preflight, :dry_run, :execute]

  def index
    @import_runs = ImportRun.includes(:company).recent_first
  end

  def new
    @import_run = ImportRun.new
    @companies = Company.order(:name)
  end

  def create
    company = Company.find(params.require(:import_run)[:company_id])
    file = params.require(:import_run)[:file]

    if file.blank?
      redirect_to new_import_run_path, alert: "Please choose a CSV file to upload." and return
    end

    @import_run = company.import_runs.create!(filename: file.original_filename, status: "uploaded")
    @import_run.save_source_csv!(file)
    @import_run.log_event!("import_uploaded", "File #{file.original_filename} uploaded.")

    redirect_to import_run_path(@import_run), notice: "Import run created. Run preflight to begin."
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing => e
    redirect_to new_import_run_path, alert: "Could not create import run: #{e.message}"
  end

  def show
    @issues = @import_run.import_issues.order(:severity, :row_number)
    @audit_events = @import_run.audit_events.chronological
    @verification_checks = verification_checks_for(@import_run)
  end

  def preflight
    if Imports::PreflightService.new(@import_run).call
      redirect_to import_run_path(@import_run), notice: "Preflight completed."
    else
      redirect_to import_run_path(@import_run), alert: "Preflight failed. See audit trail for details."
    end
  end

  def dry_run
    unless @import_run.status.in?(%w[ready blocked dry_run_completed])
      redirect_to import_run_path(@import_run), alert: "Run preflight before dry run." and return
    end

    Imports::DryRunService.new(@import_run).call
    redirect_to import_run_path(@import_run), notice: "Dry run completed."
  end

  def execute
    unless @import_run.ready_for_execution?
      redirect_to import_run_path(@import_run), alert: "Run a dry run on an unblocked import before executing." and return
    end

    Imports::ExecuteService.new(@import_run).call
    Imports::VerificationService.new(@import_run).call
    redirect_to import_run_path(@import_run), notice: "Migration executed and verified."
  rescue Imports::ExecuteService::ExecutionBlockedError
    redirect_to import_run_path(@import_run), alert: "Execution refused: blocking issues remain."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to import_run_path(@import_run), alert: "Execution failed and was rolled back: #{e.message}"
  end

  private

  def set_import_run
    @import_run = ImportRun.find(params[:id])
  end

  def verification_checks_for(import_run)
    stored = import_run.metadata["verification"]
    return [] if stored.blank?

    stored.map { |check| Imports::VerificationService::Check.new(check.symbolize_keys) }
  end
end
