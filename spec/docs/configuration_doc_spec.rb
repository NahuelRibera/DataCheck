require "rails_helper"

RSpec.describe "docs/configuration.md" do
  let(:doc) { Rails.root.join("docs/configuration.md").read }

  it "documents every environment variable read in app/ and config/" do
    files = Dir[Rails.root.join("{app,config}/**/*.{rb,yml}")].reject { |f| f.include?("/config/credentials") }
    names = files.flat_map do |file|
      File.readlines(file).reject { |l| l.strip.start_with?("#") }
          .flat_map { |l| l.scan(/ENV(?:\.fetch\(|\[)\s*["']([A-Z0-9_]+)["']/).flatten }
    end.uniq

    expect(names).to include("IMPORT_MAX_UPLOAD_BYTES", "PYTHON_BIN")
    names.reject { |n| n == "BUNDLE_GEMFILE" }.each do |name|
      expect(doc).to include("`#{name}`"), "#{name} is not documented"
    end
  end

  it "states the defaults defined in code" do
    expect(doc).to include(Imports::UploadValidator::DEFAULT_MAX_BYTES.to_s)
    expect(doc).to include(Imports::UploadValidator::SNIFF_BYTES.to_s)
    expect(doc).to include("| `max_complexity` | #{DataCheckSchema.max_complexity} |")
    expect(doc).to include("| `max_depth` | #{DataCheckSchema.max_depth} |")
  end

  it "is linked from the README" do
    expect(Rails.root.join("README.md").read).to include("docs/configuration.md")
  end
end
