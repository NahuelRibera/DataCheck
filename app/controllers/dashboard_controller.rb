class DashboardController < ApplicationController
  def show
    @total_runs = ImportRun.count
    @successful_runs = ImportRun.where(status: "completed").count
    @blocked_runs = ImportRun.where(status: "blocked").count
    @records_processed = ImportRun.sum(:source_record_count)
    @issues_detected = ImportRun.sum(:issue_count)
    @recent_runs = ImportRun.includes(:company).recent_first.limit(15)
  end
end
