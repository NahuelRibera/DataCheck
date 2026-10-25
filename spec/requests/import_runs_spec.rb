require "rails_helper"

RSpec.describe "ImportRuns", type: :request do
  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }

  describe "POST /import_runs" do
    it "creates an import run from an uploaded CSV" do
      csv = Rack::Test::UploadedFile.new(
        StringIO.new("external_id,first_name,last_name,email,department_external_id,manager_external_id,start_date,gross_salary,status\nEMP-1,Ada,Lovelace,,DEPT-ENG,,2024-01-01,50000,active\n"),
        "text/csv", original_filename: "upload.csv"
      )

      expect do
        post "/import_runs", params: { import_run: { company_id: company.id, file: csv } }
      end.to change { ImportRun.count }.by(1)

      run = ImportRun.last
      expect(run.filename).to eq("upload.csv")
      expect(File.exist?(run.source_csv_path)).to be true
      expect(response).to redirect_to(import_run_path(run))
    end

    context "with an invalid upload" do
      def upload(content, filename, type = "text/csv")
        Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)
      end

      def post_upload(file)
        expect do
          post "/import_runs", params: { import_run: { company_id: company.id, file: file } }
        end.not_to change { ImportRun.count }
        expect(response).to redirect_to(new_import_run_path)
        follow_redirect!
      end

      it "rejects files larger than the configured limit" do
        stub_const("ENV", ENV.to_hash.merge("IMPORT_MAX_UPLOAD_BYTES" => "50"))
        post_upload(upload("external_id,first_name\n" + ("EMP-1,Secret\n" * 10), "big.csv"))
        expect(response.body).to include("too large")
        expect(response.body).not_to include("Secret")
      end

      it "uses a 20 MB default limit" do
        expect(Imports::UploadValidator.max_bytes).to eq(20 * 1024 * 1024)
      end

      it "rejects a wrong extension" do
        post_upload(upload("external_id\nEMP-1\n", "data.txt", "text/plain"))
        expect(response.body).to include("must have a .csv extension")
      end

      it "rejects binary content disguised as a CSV" do
        post_upload(upload("PK\x03\x04\x00\x00binary".b, "fake.csv"))
        expect(response.body).to include("does not look like a CSV")
      end

      it "rejects an empty file" do
        post_upload(upload("", "empty.csv"))
        expect(response.body).to include("does not look like a CSV")
      end

      it "rejects a request without a file" do
        post_upload(nil)
        expect(response.body).to include("choose a CSV file")
      end
    end
  end

  describe "error messages never echo exception text" do
    let(:marker) { "SECRET-MARKER-91827" }

    def invalid_error
      record = Employee.new
      record.errors.add(:base, marker)
      ActiveRecord::RecordInvalid.new(record)
    end

    it "shows a fixed alert when creating a run raises RecordInvalid" do
      csv = Rack::Test::UploadedFile.new(StringIO.new("external_id\nEMP-1\n"), "text/csv", original_filename: "upload.csv")
      allow_any_instance_of(ImportRun).to receive(:save_source_csv!).and_raise(invalid_error)

      post "/import_runs", params: { import_run: { company_id: company.id, file: csv } }

      expect(response).to redirect_to(new_import_run_path)
      expect(flash[:alert]).to eq(ImportRunsController::CREATE_FAILED_ALERT)
      follow_redirect!
      expect(response.body).not_to include(marker)
    end

    it "redirects to the upload form with a fixed message when params are missing" do
      post "/import_runs", params: {}

      expect(response).to redirect_to(new_import_run_path)
      expect(flash[:alert]).to eq(ImportRunsController::CREATE_MISSING_PARAMS_ALERT)
    end

    it "shows a fixed rolled-back alert when execute raises RecordInvalid" do
      run = create(:import_run, company: company, status: "dry_run_completed")
      allow_any_instance_of(Imports::ExecuteService).to receive(:call).and_raise(invalid_error)

      post "/import_runs/#{run.id}/execute"

      expect(response).to redirect_to(import_run_path(run))
      expect(flash[:alert]).to eq(ImportRunsController::EXECUTE_FAILED_ALERT)
      expect(flash[:alert]).to include("rolled back")
      follow_redirect!
      expect(response.body).not_to include(marker)
    end
  end

  describe "POST /import_runs/:id/dry_run failure" do
    it "redirects with a fixed alert and keeps exception text out of the page and audit trail" do
      run = create(:import_run, company: company, status: "ready")
      allow_any_instance_of(Imports::MigrationPlan).to receive(:call).and_raise(Errno::ENOENT, "/srv/secret/ada@example.com")

      post "/import_runs/#{run.id}/dry_run"

      expect(response).to redirect_to(import_run_path(run))
      expect(flash[:alert]).to eq(ImportRunsController::DRY_RUN_FAILED_ALERT)
      expect(run.reload.status).to eq("failed")
      expect(run.audit_events.find_by!(event_type: "import_failed").message).to eq("Dry run failed (Errno::ENOENT).")
      follow_redirect!
      expect(response.body).not_to include("ada@example.com", "/srv/secret")
    end
  end

  describe "GET /import_runs/:id" do
    it "renders successfully" do
      run = create(:import_run, company: company)
      get "/import_runs/#{run.id}"
      expect(response).to have_http_status(:ok)
    end

    context "with an uploaded source CSV" do
      include CsvHelpers

      let(:run) { create(:import_run, company: company, status: "uploaded") }

      before do
        write_source_csv(run, [
          default_employee_row(external_id: "EMP-001", email: "ada@example.com"),
          default_employee_row(external_id: "EMP-001", first_name: "Grace", last_name: "Hopper", email: "", department_external_id: "DEPT-ENG"),
        ])
      end

      it "renders the column profile from the profiler" do
        get "/import_runs/#{run.id}"
        expect(response.body).to include("column-profile")
        doc = Nokogiri::HTML(response.body)
        row = doc.css("[data-testid=column-profile] tbody tr").find { |tr| tr.at_css("td").text.start_with?("external_id") }
        expect(row.css("td").map(&:text).map(&:strip)).to eq(["external_id (masked)", "text", "0", "1", "1"])
        email = doc.css("[data-testid=column-profile] tbody tr").find { |tr| tr.at_css("td").text.start_with?("email") }
        expect(email.css("td")[2].text).to eq("1")
      end

      it "masks sensitive values in the preview but shows safe ones" do
        get "/import_runs/#{run.id}"
        preview = Nokogiri::HTML(response.body).at_css("[data-testid=masked-preview]").text
        expect(preview).to include("DEPT-ENG", "***")
        %w[Ada Lovelace Grace Hopper ada@example.com 50000.00 EMP-001].each do |raw|
          expect(preview).not_to include(raw)
        end
      end

      it "renders a placeholder when the source file is gone" do
        FileUtils.rm_f(run.source_csv_path)
        get "/import_runs/#{run.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No readable source file")
      end
    end

    it "renders a 404 page for a missing run" do
      get "/import_runs/999999"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /import_runs/:id/execute" do
    it "redirects with an alert when blocked issues remain" do
      run = create(:import_run, company: company, status: "dry_run_completed", blocking_issue_count: 1)
      post "/import_runs/#{run.id}/execute"
      expect(response).to redirect_to(import_run_path(run))
      follow_redirect!
      expect(response.body).to include("unblocked import")
    end
  end

  describe "a run that changed after the controller loaded it" do
    let(:run) { create(:import_run, company: company) }

    before do
      write_source_csv(run, [default_employee_row(department_external_id: "DEPT-ENG")])
      post "/import_runs/#{run.id}/preflight"
      post "/import_runs/#{run.id}/dry_run"
    end

    it "refuses a second execute with the existing alert and one import_started event" do
      post "/import_runs/#{run.id}/execute"
      expect(run.reload.status).to eq("completed")
      allow_any_instance_of(ImportRun).to receive(:ready_for_execution?).and_return(true)

      post "/import_runs/#{run.id}/execute"

      expect(response).to redirect_to(import_run_path(run))
      expect(flash[:alert]).to eq("Run a dry run on an unblocked import before executing.")
      expect(run.audit_events.where(event_type: "import_started").count).to eq(1)
      expect(run.reload.status).to eq("completed")
      expect(Employee.count).to eq(1)
    end

    it "refuses execute when another request already started importing" do
      allow_any_instance_of(ImportRun).to receive(:ready_for_execution?) do |stale|
        ImportRun.where(id: stale.id).update_all(status: "importing")
        true
      end

      post "/import_runs/#{run.id}/execute"

      expect(response).to redirect_to(import_run_path(run))
      expect(flash[:alert]).to eq("Run a dry run on an unblocked import before executing.")
      expect(run.audit_events.where(event_type: "import_started")).to be_empty
      expect(Employee.count).to eq(0)
    end

    it "refuses preflight on a run another request is importing" do
      ImportRun.where(id: run.id).update_all(status: "importing")

      post "/import_runs/#{run.id}/preflight"

      expect(response).to redirect_to(import_run_path(run))
      expect(flash[:alert]).to eq("This import run is already being processed or completed.")
      expect(run.reload.status).to eq("importing")
    end
  end

  describe "GET /import_runs/:id issue summary" do
    let(:run) { create(:import_run, company: company) }

    let(:show_all_link) { %(href="#{import_run_path(run, anchor: 'issues')}") }

    before do
      create_list(:import_issue, 2, import_run: run, issue_type: "orphan_manager", severity: "blocking")
      create_list(:import_issue, 3, import_run: run, issue_type: "unknown_department", severity: "blocking")
      create(:import_issue, import_run: run, issue_type: "invalid_email", severity: "warning", row_number: 9)
    end

    def page
      Nokogiri::HTML(response.body)
    end

    def summary_rows
      page.css("#issue-summary tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
    end

    def listed_issues
      page.css('tr[data-issue-filter-target="row"]').map { |tr| [tr["data-severity"], tr["data-issue-type"]] }
    end

    it "shows each group's count and explanation and links it to a filtered list" do
      get "/import_runs/#{run.id}"

      explanations = ImportIssue::RULE_EXPLANATIONS
      expect(summary_rows).to eq([
        ["Blocking", "Unknown department", explanations["unknown_department"], "3"],
        ["Blocking", "Orphan manager", explanations["orphan_manager"], "2"],
        ["Warning", "Invalid email", explanations["invalid_email"], "1"],
      ])
      expect(response.body).to include(CGI.escapeHTML("/import_runs/#{run.id}?issue_type=orphan_manager&severity=blocking#issues"))
      expect(response.body).to include("Issues (6)")
      expect(response.body).not_to include(show_all_link)
    end

    it "lists only matching issues when filtered by severity and issue type" do
      get "/import_runs/#{run.id}", params: { severity: "warning", issue_type: "invalid_email" }

      expect(listed_issues).to eq([%w[warning invalid_email]])
    end

    it "filters by severity alone and keeps the full total and a Show all issues link" do
      get "/import_runs/#{run.id}", params: { severity: "warning" }

      expect(listed_issues).to eq([%w[warning invalid_email]])
      expect(summary_rows.size).to eq(3)
      expect(response.body).to include("Issues (6)")
      expect(response.body).to include(show_all_link)
    end

    it "filters by issue type alone" do
      get "/import_runs/#{run.id}", params: { issue_type: "orphan_manager" }

      expect(listed_issues).to eq([%w[blocking orphan_manager]] * 2)
      expect(response.body).to include(show_all_link)
    end
  end
end
