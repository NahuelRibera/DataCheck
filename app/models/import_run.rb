class ImportRun < ApplicationRecord
  STATUSES = %w[uploaded profiling blocked ready dry_run_completed importing completed failed].freeze

  belongs_to :company
  has_many :import_issues, dependent: :destroy
  has_many :audit_events, dependent: :destroy

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def blocked?
    blocking_issue_count.to_i > 0
  end

  def ready_for_dry_run?
    status.in?(%w[ready dry_run_completed]) && !blocked?
  end

  def ready_for_execution?
    status == "dry_run_completed" && !blocked?
  end

  def log_event!(event_type, message, metadata: {})
    audit_events.create!(event_type: event_type, message: message, metadata: metadata)
  end

  def storage_dir
    # storage/import_runs is per-environment (storage/test/import_runs in
    # test) so the test suite's cleanup never touches development/demo data
    # -- both environments otherwise share the same Rails.root on disk.
    storage_root = Rails.env.test? ? Rails.root.join("storage", "test") : Rails.root.join("storage")
    storage_root.join("import_runs", id.to_s)
  end

  def source_csv_path
    storage_dir.join("source.csv")
  end

  def normalized_csv_path
    storage_dir.join("normalized.csv")
  end

  def save_source_csv!(io)
    FileUtils.mkdir_p(storage_dir)
    File.open(source_csv_path, "wb") { |f| f.write(io.read) }
  end
end
