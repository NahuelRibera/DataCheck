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
end
