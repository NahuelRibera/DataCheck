require "rails_helper"

RSpec.describe ImportRun, type: :model do
  it "is blocked when blocking_issue_count is positive" do
    run = build(:import_run, blocking_issue_count: 2)
    expect(run.blocked?).to be true
  end

  it "is not blocked when blocking_issue_count is zero" do
    run = build(:import_run, blocking_issue_count: 0)
    expect(run.blocked?).to be false
  end

  it "logs an audit event via log_event!" do
    run = create(:import_run)
    expect { run.log_event!("import_uploaded", "File uploaded") }.to change { run.audit_events.count }.by(1)
  end
end
