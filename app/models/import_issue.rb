class ImportIssue < ApplicationRecord
  SEVERITIES = %w[warning blocking].freeze

  ISSUE_TYPES = %w[
    duplicate_external_id
    unknown_department
    orphan_manager
    invalid_date
    missing_external_id
    invalid_salary
    invalid_email
  ].freeze

  RULE_EXPLANATIONS = {
    "duplicate_external_id" => "The same employee identifier appears on more than one row. Keep one row per employee or correct the identifiers.",
    "unknown_department" => "The department identifier does not match any department of the target company. Add the department or fix the code in the file.",
    "orphan_manager" => "The manager identifier refers to someone who is neither in this file nor already in the company. Fix the reference or add the manager.",
    "invalid_date" => "The start date is missing, is not a real calendar date, or is not in one of the accepted formats: YYYY-MM-DD, MM/DD/YYYY or DD-MM-YYYY. Correct the value in the file.",
    "missing_external_id" => "The row has no employee identifier, so it cannot be matched or imported safely. Add the identifier.",
    "invalid_salary" => "The salary is missing, not numeric or out of range. Correct the value in the file.",
    "invalid_email" => "The email address is not well formed. Correct or clear the value in the file.",
  }.freeze

  SeveritySummary = Struct.new(:severity, :issue_type, :count, :explanation, keyword_init: true)

  belongs_to :import_run

  validates :issue_type, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :message, presence: true

  scope :blocking, -> { where(severity: "blocking") }
  scope :warnings, -> { where(severity: "warning") }

  scope :with_severity, ->(severity) { severity.present? ? where(severity: severity) : all }
  scope :with_issue_type, ->(type) { type.present? ? where(issue_type: type) : all }

  # Counts per (severity, rule) computed by the database, blocking first,
  # then most frequent rules first.
  def self.summary
    group(:severity, :issue_type).count.map do |(severity, type), count|
      SeveritySummary.new(severity: severity, issue_type: type, count: count,
                          explanation: RULE_EXPLANATIONS.fetch(type, "No explanation is available for this rule."))
    end.sort_by { |row| [SEVERITIES.reverse.index(row.severity), -row.count, row.issue_type] }
  end
end
