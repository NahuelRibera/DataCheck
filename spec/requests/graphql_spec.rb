require "rails_helper"

RSpec.describe "GraphQL", type: :request do
  let(:company) { create(:company) }
  let!(:import_run) { create(:import_run, company: company, status: "blocked", blocking_issue_count: 2) }
  let!(:issue) { create(:import_issue, import_run: import_run, severity: "blocking", issue_type: "orphan_manager") }

  it "returns import runs with nested issues" do
    query = <<~GRAPHQL
      {
        importRuns {
          id
          status
          blockingIssueCount
          issues(severity: "blocking") {
            issueType
            severity
          }
        }
      }
    GRAPHQL

    post "/graphql", params: { query: query }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    run_json = body["data"]["importRuns"].find { |r| r["id"] == import_run.id.to_s }
    expect(run_json["status"]).to eq("blocked")
    expect(run_json["blockingIssueCount"]).to eq(2)
    expect(run_json["issues"].first["issueType"]).to eq("orphan_manager")
  end

  it "returns a single import run by id" do
    query = "{ importRun(id: #{import_run.id}) { status } }"

    post "/graphql", params: { query: query }

    body = JSON.parse(response.body)
    expect(body["data"]["importRun"]["status"]).to eq("blocked")
  end

  it "works for a real client without a CSRF token, not only because RSpec disables forgery protection" do
    # allow_forgery_protection is off repo-wide in test (Rails' own
    # default), which would hide a regression of GraphqlController's
    # skip_forgery_protection. Turn it back on here so this spec actually
    # exercises the same authenticity check a real curl/Postman request
    # would hit in development or production.
    with_forgery_protection do
      post "/graphql", params: { query: "{ importRun(id: #{import_run.id}) { status } }" }
    end

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["importRun"]["status"]).to eq("blocked")
  end

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
