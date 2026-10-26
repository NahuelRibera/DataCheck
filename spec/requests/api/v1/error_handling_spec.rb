require "rails_helper"

RSpec.describe "Api::V1 error handling", type: :request do
  let(:import_run) { create(:import_run) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }

  it "returns a fixed 400 for a malformed JSON body" do
    post "/api/v1/import_runs/#{import_run.id}/preflight", params: '{"salary": 123456, "email": "a@b', headers: json_headers

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "bad request: malformed JSON body")
    expect(response.body).not_to include("123456", "a@b", "unexpected")
  end

  it "returns a fixed 400 for ParameterMissing without echoing the exception text" do
    allow(Imports::PreflightService).to receive(:new).and_raise(ActionController::ParameterMissing.new(:secret_key))

    post "/api/v1/import_runs/#{import_run.id}/preflight"

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "bad request: missing required parameter")
    expect(response.body).not_to include("secret_key")
  end

  it "returns a fixed 500 for unexpected failures and logs only the class name" do
    allow(Imports::PreflightService).to receive(:new).and_raise(RuntimeError, "salary 99999 for jane@example.com")
    allow(Rails.logger).to receive(:error)

    post "/api/v1/import_runs/#{import_run.id}/preflight"

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body).to eq("error" => "internal server error")
    expect(response.body).not_to include("99999", "jane@example.com")
    expect(Rails.logger).to have_received(:error).with("API request failed: RuntimeError")
    expect(Rails.logger).not_to have_received(:error).with(/99999|jane@example\.com/)
  end

  it "keeps the existing not found response" do
    get "/api/v1/import_runs/999999"

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "not found")
  end

  it "keeps the existing execution refused response" do
    allow(Imports::ExecuteService).to receive(:new).and_raise(Imports::ExecuteService::ExecutionBlockedError)
    allow_any_instance_of(ImportRun).to receive(:ready_for_execution?).and_return(true)

    post "/api/v1/import_runs/#{import_run.id}/execute"

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "execution refused: blocking issues remain")
  end
end
