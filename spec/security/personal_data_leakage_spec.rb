require "rails_helper"

# Runs the whole pipeline over a synthetic CSV whose personal values are
# unique canary strings, then asserts none of them surface in the Rails log,
# ImportIssue rows, AuditEvent rows, stored verification output or any
# rendered page / API / GraphQL response.
RSpec.describe "Personal data never leaks", type: :request do
  include CsvHelpers

  CANARIES = {
    first_good: "Zqxfirst7a1",
    last_good: "Zqxlast7a1",
    email_good: "zqx.mail7a1@canary-example.test",
    salary_good: "7351942.17",
    first_bad: "Zqxfirst7b2",
    last_bad: "Zqxlast7b2",
    email_bad: "zqx-not-an-email-7b2",
    salary_bad: "zqxsalary7b2",
    first_ghost: "Zqxfirst7c3",
    last_ghost: "Zqxlast7c3",
    email_ghost: "zqx.ghost7c3@canary-example.test",
    salary_ghost: "6284751.93",
  }.freeze

  # Strings that must never appear anywhere: each canary, plus the cents form
  # of the numeric salaries (what the normalized CSV and DB store).
  def forbidden_values
    CANARIES.values + %w[735194217 628475193]
  end

  def expect_no_canaries(text, where)
    leaked = forbidden_values.select { |value| text.to_s.include?(value) }
    expect(leaked).to be_empty, "#{where} leaked personal values: #{leaked.inspect}"
  end

  let(:company) { create(:company) }
  let!(:department) { create(:department, company: company, external_id: "DEPT-ENG") }
  let(:log_io) { StringIO.new }
  let(:log_sink) { ActiveSupport::Logger.new(log_io) }

  around do |example|
    Rails.logger.broadcast_to(log_sink)
    begin
      example.run
    ensure
      Rails.logger.stop_broadcasting_to(log_sink)
    end
  end

  def upload(rows)
    csv_string = CSV.generate(headers: true) do |csv|
      csv << CsvHelpers::HEADERS
      rows.each { |row| csv << CsvHelpers::HEADERS.map { |header| row[header.to_sym] } }
    end
    file = Rack::Test::UploadedFile.new(StringIO.new(csv_string), "text/csv", original_filename: "canary.csv")
    post "/import_runs", params: { import_run: { company_id: company.id, file: file } }
    ImportRun.order(:id).last
  end

  def all_stored_text(run)
    [
      run.reload.attributes.to_json,
      run.import_issues.map { |i| i.attributes.to_json },
      run.audit_events.map { |e| e.attributes.to_json },
    ].flatten.join("\n")
  end

  it "keeps canaries out of logs, issues, audit events and responses across the pipeline" do
    rendered = []
    run = upload([
      default_employee_row(external_id: "EMP-1", first_name: CANARIES[:first_good], last_name: CANARIES[:last_good],
                           email: CANARIES[:email_good], gross_salary: CANARIES[:salary_good], department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", first_name: CANARIES[:first_bad], last_name: CANARIES[:last_bad],
                           email: CANARIES[:email_bad], gross_salary: CANARIES[:salary_bad], manager_external_id: "EMP-1"),
      default_employee_row(external_id: "EMP-3", first_name: CANARIES[:first_ghost], last_name: CANARIES[:last_ghost],
                           email: CANARIES[:email_ghost], gross_salary: CANARIES[:salary_ghost], department_external_id: "DEPT-GHOST"),
    ])
    rendered << response.body

    post "/import_runs/#{run.id}/preflight"
    get "/import_runs/#{run.id}"
    rendered << response.body
    run.reload
    expect(run.import_issues.count).to be >= 3 # the canary rows really produced issues
    expect(run).to be_blocked

    # Blocked execution is refused; the refusal is audited and rendered.
    post "/import_runs/#{run.id}/execute"
    rendered << flash.to_h.to_json

    # Drop the blocked row so the rest of the pipeline can run, then re-preflight.
    write_source_csv(run, [
      default_employee_row(external_id: "EMP-1", first_name: CANARIES[:first_good], last_name: CANARIES[:last_good],
                           email: CANARIES[:email_good], gross_salary: CANARIES[:salary_good], department_external_id: "DEPT-ENG"),
      default_employee_row(external_id: "EMP-2", first_name: CANARIES[:first_bad], last_name: CANARIES[:last_bad],
                           email: CANARIES[:email_bad], gross_salary: "100.00", manager_external_id: "EMP-1"),
    ])
    post "/import_runs/#{run.id}/preflight"
    post "/import_runs/#{run.id}/dry_run"
    get "/import_runs/#{run.id}"
    rendered << response.body
    post "/import_runs/#{run.id}/execute"
    rendered << flash.to_h.to_json
    expect(run.reload.status).to eq("completed")
    expect(Employee.where(company: company).count).to eq(2) # the data really was imported

    get "/import_runs/#{run.id}"
    rendered << response.body
    get "/import_runs"
    rendered << response.body
    get "/api/v1/import_runs/#{run.id}"
    rendered << response.body
    get "/api/v1/import_runs/#{run.id}/issues"
    rendered << response.body
    get "/api/v1/import_runs/#{run.id}/verification"
    rendered << response.body
    post "/graphql", params: { query: "{ importRuns { id importIssues { message fieldName } } }" }
    rendered << response.body

    # Error pages.
    get "/import_runs/0"
    rendered << response.body
    get "/api/v1/import_runs/0/issues"
    rendered << response.body

    expect_no_canaries(log_io.string, "Rails log")
    expect_no_canaries(all_stored_text(run), "ImportRun / ImportIssue / AuditEvent records")
    expect_no_canaries(rendered.join("\n"), "rendered responses")
  end

  it "keeps canaries out of audit events and the log when the profiler cannot read the file" do
    run = create(:import_run, company: company, status: "uploaded")
    FileUtils.mkdir_p(run.storage_dir)
    File.binwrite(run.source_csv_path, "external_id,first_name\nEMP-1,#{CANARIES[:first_good]}\xFF\xFE\x00\"#{CANARIES[:last_good]}\n")

    post "/import_runs/#{run.id}/preflight"
    get "/import_runs/#{run.id}"

    expect_no_canaries(log_io.string, "Rails log")
    expect_no_canaries(all_stored_text(run), "ImportRun / AuditEvent records")
    expect_no_canaries(response.body, "show page")
  end

  it "filters every sensitive field used by the import forms and CSV columns from parameter logging" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    sensitive = %w[first_name last_name email salary gross_salary gross_salary_cents]
    filtered = filter.filter(sensitive.index_with { |_| "canary" }.merge("import_run" => { "email" => "canary" }))
    sensitive.each { |key| expect(filtered[key]).to eq("[FILTERED]") }
    expect(filtered["import_run"]["email"]).to eq("[FILTERED]")
  end
end
