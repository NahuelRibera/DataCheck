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

  it "rejects an over-complex query with a GraphQL error" do
    selection = "id companyName filename status sourceRecordCount validRecordCount issueCount " \
                "blockingIssueCount createCount updateCount skipCount rejectCount createdAt " \
                "issues { id rowNumber externalId issueType severity fieldName message }"
    query = "{ " + (1..15).map { |i| "r#{i}: importRuns { #{selection} }" }.join(" ") + " }"

    post "/graphql", params: { query: query }

    body = JSON.parse(response.body)
    expect(body["data"]).to be_nil
    expect(body["errors"].first["message"]).to match(/complexity/i)
  end

  describe "importRuns cap" do
    let(:cap) { Types::QueryType::MAX_IMPORT_RUNS }

    def fetch_ids
      post "/graphql", params: { query: "{ importRuns { id } }" }
      JSON.parse(response.body)["data"]["importRuns"].map { |r| r["id"].to_i }
    end

    it "returns all runs when fewer than the cap exist" do
      create_list(:import_run, 2, company: company)

      expect(fetch_ids.size).to eq(3)
    end

    it "returns only the newest runs, newest first, when more than the cap exist" do
      import_run.update!(created_at: 1.year.ago)
      runs = Array.new(cap + 3) { |i| create(:import_run, company: company, created_at: i.minutes.ago) }

      expect(fetch_ids).to eq(runs.first(cap).map(&:id))
    end
  end

  describe "variables parameter" do
    let(:query) { "query($id: ID!) { importRun(id: $id) { status } }" }

    def expect_generic_bad_request(secret)
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_an(Array)
      expect(body["errors"].first["message"]).to be_present
      expect(response.body).not_to include(secret)
      expect(response.body).not_to match(/backtrace|\.rb:\d+/)
    end

    it "returns 400 for malformed JSON" do
      post "/graphql", params: { query: query, variables: '{"id": "leak-me-1' }

      expect_generic_bad_request("leak-me-1")
    end

    it "returns 400 for JSON that is not an object" do
      post "/graphql", params: { query: query, variables: '["leak-me-2"]' }

      expect_generic_bad_request("leak-me-2")
    end

    it "returns 400 for an unexpected variables type" do
      post "/graphql", params: { query: query, variables: ["leak-me-3"] }

      expect_generic_bad_request("leak-me-3")
    end

    it "still accepts valid JSON string variables" do
      post "/graphql", params: { query: query, variables: { id: import_run.id }.to_json }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["importRun"]["status"]).to eq("blocked")
    end

    it "still accepts a blank variables value" do
      post "/graphql", params: { query: "{ importRun(id: #{import_run.id}) { status } }", variables: "" }

      expect(response).to have_http_status(:ok)
    end
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
