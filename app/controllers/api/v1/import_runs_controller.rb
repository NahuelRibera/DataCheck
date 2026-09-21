module Api
  module V1
    class ImportRunsController < BaseController
      before_action :set_import_run, only: [:show, :issues, :preflight, :dry_run, :execute, :verification]

      def index
        runs = ImportRun.includes(:company).recent_first
        render json: runs.map { |run| serialize_run(run) }
      end

      def show
        render json: serialize_run(@import_run, detailed: true)
      end

      def issues
        render json: @import_run.import_issues.order(:severity, :row_number).map { |issue| serialize_issue(issue) }
      end

      def preflight
        if Imports::PreflightService.new(@import_run).call
          render json: serialize_run(@import_run.reload, detailed: true)
        else
          render json: { error: "preflight failed", import_run: serialize_run(@import_run.reload) }, status: :unprocessable_content
        end
      end

      def dry_run
        unless @import_run.status.in?(%w[ready blocked dry_run_completed])
          return render json: { error: "run preflight before dry run" }, status: :unprocessable_content
        end

        Imports::DryRunService.new(@import_run).call
        render json: serialize_run(@import_run.reload, detailed: true)
      end

      def execute
        unless @import_run.ready_for_execution?
          return render json: { error: "run a dry run on an unblocked import before executing" }, status: :unprocessable_content
        end

        Imports::ExecuteService.new(@import_run).call
        Imports::VerificationService.new(@import_run).call
        render json: serialize_run(@import_run.reload, detailed: true)
      end

      def verification
        unless @import_run.status == "completed"
          return render json: { error: "import has not been executed yet" }, status: :unprocessable_content
        end

        checks = Imports::VerificationService.new(@import_run).call
        render json: checks.map(&:to_h)
      end

      private

      def set_import_run
        @import_run = ImportRun.find(params[:id])
      end

      def serialize_run(run, detailed: false)
        base = {
          id: run.id,
          company: run.company.name,
          filename: run.filename,
          status: run.status,
          source_record_count: run.source_record_count,
          valid_record_count: run.valid_record_count,
          issue_count: run.issue_count,
          blocking_issue_count: run.blocking_issue_count,
          create_count: run.create_count,
          update_count: run.update_count,
          skip_count: run.skip_count,
          reject_count: run.reject_count,
          created_at: run.created_at,
        }
        return base unless detailed

        base.merge(started_at: run.started_at, completed_at: run.completed_at)
      end

      def serialize_issue(issue)
        {
          id: issue.id,
          row_number: issue.row_number,
          external_id: issue.external_id,
          issue_type: issue.issue_type,
          severity: issue.severity,
          field_name: issue.field_name,
          message: issue.message,
        }
      end
    end
  end
end
