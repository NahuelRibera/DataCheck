require "rails_helper"

RSpec.describe "docs/import-workflow.md" do
  let(:doc) { Rails.root.join("docs/import-workflow.md").read }

  it "is linked from the README" do
    expect(Rails.root.join("README.md").read).to include("docs/import-workflow.md")
  end

  it "documents every import run status" do
    ImportRun::STATUSES.each { |status| expect(doc).to include("`#{status}`") }
  end

  it "documents the upload limit configuration" do
    expect(doc).to include("IMPORT_MAX_UPLOAD_BYTES")
    expect(doc).to include(".csv")
  end

  it "documents every verification check by name" do
    source = Rails.root.join("app/services/imports/verification_service.rb").read
    names = source.scan(/build_check\("(\w+)"/).flatten.uniq
    expect(names).not_to be_empty
    names.each { |name| expect(doc).to include("`#{name}`") }
  end
end
