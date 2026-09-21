require "rails_helper"

RSpec.describe "ImportRun file storage", type: :model do
  it "stores files under storage/test, not storage/ shared with development" do
    run = create(:import_run)
    expect(run.storage_dir.to_s).to include("/storage/test/import_runs/")
  end
end
