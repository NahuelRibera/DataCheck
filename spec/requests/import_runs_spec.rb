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
  end

  describe "GET /import_runs/:id" do
    it "renders successfully" do
      run = create(:import_run, company: company)
      get "/import_runs/#{run.id}"
      expect(response).to have_http_status(:ok)
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
end
