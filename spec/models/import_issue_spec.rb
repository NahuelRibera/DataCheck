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

  describe ".summary" do
    let(:run) { create(:import_run) }

    before do
      create_list(:import_issue, 2, import_run: run, issue_type: "orphan_manager", severity: "blocking")
      create_list(:import_issue, 3, import_run: run, issue_type: "unknown_department", severity: "blocking")
      create(:import_issue, import_run: run, issue_type: "invalid_email", severity: "warning")
      create_list(:import_issue, 3, import_run: run, issue_type: "invalid_email", severity: "warning")
      create(:import_issue, import_run: create(:import_run), issue_type: "orphan_manager", severity: "blocking")
    end

    it "groups by severity and rule with database counts, blocking first then most frequent" do
      rows = run.import_issues.summary
      expect(rows.map { |r| [r.severity, r.issue_type, r.count] }).to eq(
        [["blocking", "unknown_department", 3], ["blocking", "orphan_manager", 2], ["warning", "invalid_email", 4]]
      )
      expect(rows.map(&:explanation)).to eq(ImportIssue::RULE_EXPLANATIONS.values_at("unknown_department", "orphan_manager", "invalid_email"))
    end

    it "aggregates with a single GROUP BY query instead of loading issues" do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { run.import_issues.summary }

      expect(queries.size).to eq(1)
      expect(queries.first).to match(/COUNT\(\*\).*GROUP BY/i)
    end

    it "filters by severity and issue type" do
      expect(run.import_issues.with_severity("warning").count).to eq(4)
      expect(run.import_issues.with_issue_type("orphan_manager").count).to eq(2)
      expect(run.import_issues.with_severity(nil).count).to eq(9)
    end

    it "has an explanation for every known rule" do
      expect(ImportIssue::RULE_EXPLANATIONS.keys).to match_array(ImportIssue::ISSUE_TYPES)
    end

    it "names every date format the profiler accepts in the invalid_date explanation" do
      expect(ImportIssue::RULE_EXPLANATIONS["invalid_date"]).to include("YYYY-MM-DD", "MM/DD/YYYY", "DD-MM-YYYY")
    end
  end
end
