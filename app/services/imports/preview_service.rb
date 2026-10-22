require "open3"
require "json"

module Imports
  # Runs the Python profiler in --preview-only mode to get a per-column
  # profile and a masked preview of the uploaded CSV. Masking happens inside
  # the profiler, so raw sensitive values never reach Rails. Read-only: no
  # database writes. Returns nil when the file is missing or unreadable.
  class PreviewService
    PYTHON_BIN = PreflightService::PYTHON_BIN
    SCRIPT_PATH = PreflightService::SCRIPT_PATH
    PREVIEW_ROWS = 5

    def initialize(import_run)
      @import_run = import_run
    end

    def call
      path = import_run.source_csv_path
      return nil unless File.exist?(path)

      Rails.cache.fetch(cache_key(path), skip_nil: true) { run_profiler(path) }
    rescue SystemCallError => e
      Rails.logger.warn("[Imports::PreviewService] #{e.class}")
      nil
    end

    private

    attr_reader :import_run

    # Keyed by run id, file size and mtime so replacing the file invalidates
    # the entry. Failures return nil, which Rails.cache.fetch does not store
    # (skip_nil).
    def cache_key(path)
      stat = File.stat(path)
      ["imports/preview/v1", import_run.id, stat.size, stat.mtime.to_i, stat.mtime.nsec, PREVIEW_ROWS].join("/")
    end

    def run_profiler(path)
      stdout, stderr, status = Open3.capture3(
        PYTHON_BIN, SCRIPT_PATH.to_s,
        "--csv", path.to_s,
        "--preview-only", "--preview-rows", PREVIEW_ROWS.to_s
      )
      unless status.success?
        Rails.logger.warn("[Imports::PreviewService] profiler exited with status #{status.exitstatus} stderr=#{stderr.to_s.truncate(200)}")
        return nil
      end

      result = JSON.parse(stdout)
      result["error"].present? ? nil : result
    rescue JSON::ParserError, SystemCallError => e
      Rails.logger.warn("[Imports::PreviewService] #{e.class}")
      nil
    end
  end
end
