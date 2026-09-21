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

  belongs_to :import_run

  validates :issue_type, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :message, presence: true

  scope :blocking, -> { where(severity: "blocking") }
  scope :warnings, -> { where(severity: "warning") }
end
