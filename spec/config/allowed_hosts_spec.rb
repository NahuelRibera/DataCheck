require "rails_helper"
require Rails.root.join("config/allowed_hosts")

RSpec.describe AllowedHosts do
  describe ".parse" do
    it "splits comma-separated values and strips whitespace" do
      expect(described_class.parse(" a.example.com , b.example.com")).to eq(%w[a.example.com b.example.com])
    end

    it "drops blank entries" do
      expect(described_class.parse(",, a.example.com ,  ,")).to eq(%w[a.example.com])
    end

    it "returns an empty list when unset or blank" do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse("  ")).to eq([])
    end

    it "refuses an entry starting with a dot, which Rails reads as a subdomain wildcard" do
      expect { described_class.parse("app.example.com, .example.com") }
        .to raise_error(described_class::InvalidEntry, /"\.example\.com" starts with a dot/)
    end

    it "refuses a leading dot hidden behind whitespace" do
      expect { described_class.parse("  .example.com") }.to raise_error(described_class::InvalidEntry)
    end

    it "accepts dots inside a host name" do
      expect(described_class.parse("a.b.example.com")).to eq(%w[a.b.example.com])
    end
  end

  describe "host authorization with the production settings" do
    let(:inner) { ->(_env) { [200, { "Content-Type" => "text/plain" }, ["ok"]] } }
    let(:app) do
      ActionDispatch::HostAuthorization.new(
        inner, described_class.parse("app.example.com, "),
        exclude: described_class::EXCLUDE_HEALTH_CHECK
      )
    end

    def get_status(path, host)
      app.call(Rack::MockRequest.env_for("http://#{host}#{path}", "HTTP_HOST" => host)).first
    end

    it "accepts a listed host" do
      expect(get_status("/", "app.example.com")).to eq(200)
    end

    it "refuses an unlisted host" do
      expect(get_status("/", "evil.example.net")).to eq(403)
    end

    it "answers /up for any host" do
      expect(get_status("/up", "evil.example.net")).to eq(200)
    end
  end
end
