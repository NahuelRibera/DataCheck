class ImportRun < ApplicationRecord
  STATUSES = %w[uploaded profiling blocked ready dry_run_completed importing completed failed].freeze
  # A step is running and owns the run's files and counters; no other step
  # may start until it finishes.
  IN_PROGRESS_STATUSES = %w[profiling importing].freeze
  # A step still in progress after this long died with its process (the migration's own transaction has
  # rolled back), and preflight may start the run over, as it always could.
  IN_PROGRESS_EXPIRES_AFTER = 1.hour

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

  # Re-reads this run under SELECT ... FOR UPDATE and raises
  # Imports::StaleStateError if its current status is one of +refused+,
  # then yields inside the same transaction, so the check and the
  # transition the block makes cannot interleave with another request.
  #
  # reload(lock: true) rather than with_lock/lock!: the decision must come
  # from the locked row, and lock! refuses a record with unsaved changes
  # instead of discarding them.
  #
  # With +take_over_expired+, an in-progress status older than IN_PROGRESS_EXPIRES_AFTER is not refused;
  # the block receives that status so the caller can record what it recovered from.
  def with_status_lock(refused:, take_over_expired: false)
    transaction do
      reload(lock: true)
      expired = take_over_expired && status.in?(IN_PROGRESS_STATUSES) && updated_at < IN_PROGRESS_EXPIRES_AFTER.ago
      raise Imports::StaleStateError, "import run is #{status}" if status.in?(refused) && !expired

      yield(expired ? status : nil)
    end
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

  DIR_MODE = 0o700
  FILE_MODE = 0o600

  def save_source_csv!(io)
    ensure_private_storage_dir!
    # Chunked copy: memory use stays flat however large the upload is.
    # The mode only applies on creation and is masked by the umask, so it is
    # set explicitly as well.
    File.open(source_csv_path, "wb", FILE_MODE) do |f|
      f.chmod(FILE_MODE)
      IO.copy_stream(io, f)
    end
  end

  # Creates normalized.csv owner-only before the profiler writes into it
  # (the profiler truncates the existing file and so keeps its mode).
  def prepare_normalized_csv!
    ensure_private_storage_dir!
    File.open(normalized_csv_path, "wb", FILE_MODE) { |f| f.chmod(FILE_MODE) }
  end

  def restrict_normalized_csv!
    File.chmod(FILE_MODE, normalized_csv_path) if File.exist?(normalized_csv_path)
  end

  private

  def ensure_private_storage_dir!
    FileUtils.mkdir_p(storage_dir, mode: DIR_MODE)
    File.chmod(DIR_MODE, storage_dir)
  end
end
