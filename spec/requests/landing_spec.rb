require "rails_helper"

RSpec.describe "Landing page", type: :request do
  describe "GET /" do
    before { get "/" }

    it "renders publicly with a single h1 and a main landmark" do
      expect(response).to have_http_status(:ok)
      expect(response.body.scan("<h1").size).to eq(1)
      expect(response.body).to include('<main class="app-main" id="main">')
    end

    it "explains the workflow steps" do
      %w[Preflight Dry\ run Execute Verify Audit].each do |step|
        expect(response.body).to include(step)
      end
    end

    it "links to the dashboard and the documentation" do
      expect(response.body).to include('href="/dashboard"')
      expect(response.body).to include("docs/architecture.md")
    end
  end

  describe "GET /dashboard" do
    it "renders the dashboard" do
      get "/dashboard"
      expect(response).to have_http_status(:ok)
    end
  end
end
