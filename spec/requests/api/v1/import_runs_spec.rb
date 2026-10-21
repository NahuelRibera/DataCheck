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

    it "filters the list by issue type alone without narrowing the summary" do
      create_list(:import_issue, 2, import_run: import_run, issue_type: "orphan_manager", severity: "blocking")
      create(:import_issue, import_run: import_run, issue_type: "unknown_department", severity: "blocking")

      get "/api/v1/import_runs/#{import_run.id}/issues", params: { issue_type: "orphan_manager" }

      body = JSON.parse(response.body)
      expect(body["issues"].map { |i| i["issue_type"] }).to eq(%w[orphan_manager orphan_manager])
      expect(body["summary"].sum { |r| r["count"] }).to eq(3)
    end
  end

  describe "error states" do
    let(:personal_values) { %w[Ada Lovelace ada@example.com 50000.00] }

    def expect_error(status, message)
      expect(response).to have_http_status(status)
      expect(JSON.parse(response.body)).to eq("error" => message)
      personal_values.each { |value| expect(response.body).not_to include(value) }
    end

    it "rejects verification before execution with an error message" do
      run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])

      get "/api/v1/import_runs/#{import_run.id}/verification"

      expect_error(:unprocessable_content, "import has not been executed yet")
    end

    it "rejects dry run before preflight with an error message" do
      post "/api/v1/import_runs/#{import_run.id}/dry_run"

      expect_error(:unprocessable_content, "run preflight before dry run")
    end

    it "rejects execute without a prior dry run and writes nothing" do
      run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])

      post "/api/v1/import_runs/#{import_run.id}/execute"

      expect_error(:unprocessable_content, "run a dry run on an unblocked import before executing")
      expect(Employee.count).to eq(0)
    end

    it "rejects execute of a blocked run without leaking row values" do
      run_preflight([default_employee_row(department_external_id: "DEPT-GHOST")])

      post "/api/v1/import_runs/#{import_run.id}/execute"

      expect_error(:unprocessable_content, "run a dry run on an unblocked import before executing")
    end

    # The controller's pre-check reads the run once; these simulate a second
    # request moving it on between that read and the service's row lock.
    context "when the run changed after the controller loaded it" do
      before do
        run_preflight([default_employee_row(department_external_id: "DEPT-ENG")])
        post "/api/v1/import_runs/#{import_run.id}/dry_run"
      end

      it "refuses a second execute with the existing error and one import_started event" do
        post "/api/v1/import_runs/#{import_run.id}/execute"
        expect(response).to have_http_status(:ok)
        allow_any_instance_of(ImportRun).to receive(:ready_for_execution?).and_return(true)

        post "/api/v1/import_runs/#{import_run.id}/execute"

        expect_error(:unprocessable_content, "run a dry run on an unblocked import before executing")
        expect(import_run.audit_events.where(event_type: "import_started").count).to eq(1)
        expect(import_run.reload.status).to eq("completed")
        expect(Employee.count).to eq(1)
      end

      it "refuses execute when another request already started importing" do
        allow_any_instance_of(ImportRun).to receive(:ready_for_execution?) do |run|
          ImportRun.where(id: run.id).update_all(status: "importing")
          true
        end

        post "/api/v1/import_runs/#{import_run.id}/execute"

        expect_error(:unprocessable_content, "run a dry run on an unblocked import before executing")
        expect(import_run.audit_events.where(event_type: "import_started")).to be_empty
        expect(import_run.reload.status).to eq("importing")
        expect(Employee.count).to eq(0)
      end

      it "answers a run that became blocked under the lock with the existing blocked 422" do
        allow_any_instance_of(ImportRun).to receive(:ready_for_execution?) do |run|
          ImportRun.where(id: run.id).update_all(blocking_issue_count: 1)
          true
        end

        post "/api/v1/import_runs/#{import_run.id}/execute"

        expect_error(:unprocessable_content, "execution refused: blocking issues remain")
        expect(import_run.audit_events.pluck(:event_type)).to include("execution_blocked")
        expect(Employee.count).to eq(0)
      end

      it "refuses a dry run on a run another request is importing" do
        allow_any_instance_of(ImportRun).to receive(:status).and_wrap_original do |original|
          ImportRun.where(id: import_run.id).update_all(status: "importing")
          original.call
        end

        post "/api/v1/import_runs/#{import_run.id}/dry_run"

        expect_error(:unprocessable_content, "import run is already being processed or completed")
      end

      it "refuses preflight on a run another request is importing" do
        ImportRun.where(id: import_run.id).update_all(status: "importing")

        post "/api/v1/import_runs/#{import_run.id}/preflight"

        expect_error(:unprocessable_content, "import run is already being processed or completed")
        expect(import_run.reload.status).to eq("importing")
      end
    end

    {
      "GET" => %w[show issues verification],
      "POST" => %w[preflight dry_run execute],
    }.each do |verb, actions|
      actions.each do |action|
        it "returns 404 for an unknown id on #{verb} #{action}" do
          path = action == "show" ? "/api/v1/import_runs/999999" : "/api/v1/import_runs/999999/#{action}"

          public_send(verb.downcase, path)

          expect_error(:not_found, "not found")
        end
      end
    end
  end
end
