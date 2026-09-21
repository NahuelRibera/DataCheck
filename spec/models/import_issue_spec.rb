require "rails_helper"

RSpec.describe ImportIssue, type: :model do
  it "requires severity to be warning or blocking" do
    issue = build(:import_issue, severity: "critical")
    expect(issue).not_to be_valid
  end

  it "is enforced at the database level too" do
    run = create(:import_run)
    issue = run.import_issues.build(issue_type: "x", severity: "critical", message: "bad", row_number: 1)
    expect { issue.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
