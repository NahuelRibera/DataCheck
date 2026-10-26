require "rails_helper"
require "json"
require "open3"

# Boots the real app with RAILS_ENV=production in a child process, so these
# examples exercise config/environments/production.rb itself rather than a
# hand-built middleware. No database connection is made: none of the
# requests below reach a controller that queries it.
RSpec.describe "Host authorization in the production environment" do
  let(:marker) { "ALLOWED_HOSTS_RESULT " }
  let(:probe) do
    <<~RUBY
      app = Rails.application
      statuses = %w[app.example.com sub.app.example.com evil.example.net].to_h do |host|
        [host, %w[/no-such-page /up].to_h do |path|
          env = Rack::MockRequest.env_for("https://\#{host}\#{path}", "HTTP_HOST" => host)
          [path, app.call(env).first]
        end]
      end
      puts "#{marker}" + JSON.generate("hosts" => app.config.hosts.map(&:to_s), "statuses" => statuses)
    RUBY
  end

  def boot_production(allowed_hosts)
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "production-boot-spec",
      "RAILS_LOG_LEVEL" => "fatal",
      "DATA_CHECK_ALLOWED_HOSTS" => allowed_hosts
    }
    Open3.capture3(env, Gem.ruby, "bin/rails", "runner", probe, chdir: Rails.root.to_s)
  end

  def probe_result(stdout)
    line = stdout.lines.find { |l| l.start_with?(marker) }
    raise "production boot printed no result:\n#{stdout}" unless line

    JSON.parse(line.delete_prefix(marker))
  end

  it "refuses unlisted hosts, accepts listed ones and answers /up for any host" do
    stdout, stderr, status = boot_production(" app.example.com , ")
    expect(status).to be_success, stderr

    result = probe_result(stdout)
    expect(result["hosts"]).to eq(["app.example.com"])
    expect(result["statuses"]).to eq(
      "app.example.com" => { "/no-such-page" => 404, "/up" => 200 },
      "sub.app.example.com" => { "/no-such-page" => 403, "/up" => 200 },
      "evil.example.net" => { "/no-such-page" => 403, "/up" => 200 }
    )
  end

  it "leaves host authorization unchanged when the variable is unset" do
    stdout, stderr, status = boot_production(nil)
    expect(status).to be_success, stderr

    result = probe_result(stdout)
    expect(result["hosts"]).to eq([])
    expect(result["statuses"]["evil.example.net"]).to eq("/no-such-page" => 404, "/up" => 200)
  end

  it "does not boot when an entry starts with a dot" do
    stdout, stderr, status = boot_production("app.example.com,.example.com")

    expect(status).not_to be_success
    expect(stderr).to include("AllowedHosts::InvalidEntry", '".example.com" starts with a dot')
    expect(stdout).not_to include(marker)
  end
end
