require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  def directives(response)
    response.headers["Content-Security-Policy"].split(";").map(&:strip).to_h do |d|
      name, *values = d.split(" ")
      [name, values]
    end
  end

  shared_examples "an enforced policy" do
    it "sends the key directives" do
      expect(response.headers["Content-Security-Policy-Report-Only"]).to be_nil
      csp = directives(response)
      expect(csp["default-src"]).to eq(["'self'"])
      expect(csp["object-src"]).to eq(["'none'"])
      expect(csp["frame-ancestors"]).to eq(["'none'"])
      expect(csp["base-uri"]).to eq(["'self'"])
    end

    it "allows only same-origin scripts" do
      expect(directives(response)["script-src"]).to eq(["'self'"])
      expect(response.body).not_to match(/<script(?![^>]*\ssrc=)/)
    end
  end

  describe "landing page" do
    before { get "/" }

    include_examples "an enforced policy"
  end

  describe "import run page" do
    before { get "/import_runs/#{create(:import_run).id}" }

    include_examples "an enforced policy"
  end

  describe "dashboard" do
    before { get "/dashboard" }

    include_examples "an enforced policy"
  end
end
