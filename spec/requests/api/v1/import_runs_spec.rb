require "rails_helper"

RSpec.describe "Api::V1::ImportRuns", type: :request do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:import_run) { create(:import_run, company: company) }

  def run_preflight(rows)
    write_source_csv(import_run, rows)
    Imports::PreflightService.new(import_run).call
    import_run.reload
  end

  describe "GET /api/v1/import_runs" do
    it "returns runs as JSON" do
      import_run
      get "/api/v1/import_runs"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.first["id"]).to eq(import_run.id)
    end
  end

  describe "GET /api/v1/import_runs/:id" do
    it "returns 200 for an existing run" do
      get "/api/v1/import_runs/#{import_run.id}"
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a nonexistent run" do
      get "/api/v1/import_runs/999999"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/import_runs/:id/preflight" do
    it "profiles the file and returns updated counts" do
      write_source_csv(import_run, [default_employee_row(department_external_id: "DEPT-ENG")])

      post "/api/v1/import_runs/#{import_run.id}/preflight"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ready")
      expect(body["valid_record_count"]).to eq(1)
    end
  end

  describe "POST /api/v1/import_runs/:id/dry_run" do
    it "returns 422 when preflight has not run yet" do
      post "/api/v1/import_runs/#{import_run.id}/dry_run"
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "computes counts once preflight has run" do
      run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])

      post "/api/v1/import_runs/#{import_run.id}/dry_run"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["create_count"]).to eq(1)
    end
  end

  describe "POST /api/v1/import_runs/:id/execute" do
    it "returns 422 when the run is blocked" do
      run_preflight([default_employee_row(department_external_id: "DEPT-GHOST")])

      post "/api/v1/import_runs/#{import_run.id}/execute"

      expect(response).to have_http_status(:unprocessable_content)
      expect(Employee.count).to eq(0)
    end

    it "executes and verifies a clean dry-run" do
      run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])
      post "/api/v1/import_runs/#{import_run.id}/dry_run"

      post "/api/v1/import_runs/#{import_run.id}/execute"

      expect(response).to have_http_status(:ok)
      expect(Employee.count).to eq(1)
    end
  end

  describe "GET /api/v1/import_runs/:id/verification" do
    it "returns 422 before the run has completed" do
      get "/api/v1/import_runs/#{import_run.id}/verification"
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns check results after a completed run" do
      run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])
      post "/api/v1/import_runs/#{import_run.id}/dry_run"
      post "/api/v1/import_runs/#{import_run.id}/execute"

      get "/api/v1/import_runs/#{import_run.id}/verification"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to all(include("status" => "pass"))
    end
  end

  describe "GET /api/v1/import_runs/:id/issues" do
    it "returns the issues for a run" do
      run_preflight([default_employee_row(department_external_id: "DEPT-GHOST")])

      get "/api/v1/import_runs/#{import_run.id}/issues"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["issues"].first["issue_type"]).to eq("unknown_department")
    end

    it "returns a summary grouped by severity and rule and filters the list" do
      create_list(:import_issue, 2, import_run: import_run, issue_type: "orphan_manager", severity: "blocking")
      create(:import_issue, import_run: import_run, issue_type: "invalid_email", severity: "warning")

      get "/api/v1/import_runs/#{import_run.id}/issues", params: { severity: "warning" }

      body = JSON.parse(response.body)
      expect(body["summary"].map { |r| r.slice("severity", "issue_type", "count") }).to eq(
        [{ "severity" => "blocking", "issue_type" => "orphan_manager", "count" => 2 },
         { "severity" => "warning", "issue_type" => "invalid_email", "count" => 1 }]
      )
      expect(body["summary"].first["explanation"]).to be_present
      expect(body["issues"].map { |i| i["issue_type"] }).to eq(["invalid_email"])
    end
  end
end
