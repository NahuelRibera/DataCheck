class AuditEvent < ApplicationRecord
  EVENT_TYPES = %w[
    import_uploaded
    preflight_started
    preflight_completed
    issues_detected
    safe_normalization_completed
    dry_run_started
    dry_run_completed
    import_started
    import_completed
    verification_completed
    import_failed
    execution_blocked
  ].freeze

  belongs_to :import_run

  validates :event_type, presence: true
  validates :message, presence: true

  scope :chronological, -> { order(created_at: :asc) }
end
