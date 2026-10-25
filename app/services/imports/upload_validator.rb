module Imports
  # Checks an uploaded file before it is stored or handed to the profiler.
  # Messages never include file contents or the client-supplied filename.
  class UploadValidator
    DEFAULT_MAX_BYTES = 20 * 1024 * 1024
    SNIFF_BYTES = 8192
    HEADER_BYTES = 64 * 1024
    # Must match REQUIRED_COLUMNS in scripts/profile_import.py (checked by a spec).
    REQUIRED_COLUMNS = %w[external_id first_name last_name department_external_id start_date gross_salary].freeze

    def self.max_bytes
      configured = Integer(ENV.fetch("IMPORT_MAX_UPLOAD_BYTES", DEFAULT_MAX_BYTES), exception: false)
      configured && configured > 0 ? configured : DEFAULT_MAX_BYTES
    end

    # Returns an error message, or nil when the upload is acceptable.
    def self.error_for(file)
      new(file).error
    end

    def initialize(file)
      @file = file
    end

    def error
      return "Please choose a CSV file to upload." if @file.blank? || !@file.respond_to?(:original_filename)
      return "The file must have a .csv extension." unless File.extname(@file.original_filename.to_s).casecmp?(".csv")

      limit = self.class.max_bytes
      if @file.size > limit
        return "The file is too large. The maximum upload size is #{format_size(limit)}."
      end

      return "The file does not look like a CSV text file." unless csv_like?

      header_error
    end

    private

    # Mirrors scripts/profile_import.py: names are stripped, a leading BOM is
    # ignored and only the column names are reported, never cell values.
    def header_error
      columns = header_columns
      return "The header row could not be read. Check that the first line lists the column names." if columns.nil?

      missing = REQUIRED_COLUMNS - columns
      return nil if missing.empty?

      "The file is missing required columns: #{missing.join(', ')}."
    end

    def header_columns
      @file.rewind
      text = @file.read(HEADER_BYTES).to_s.b.delete_prefix("\xEF\xBB\xBF".b)
      line = text.force_encoding(Encoding::UTF_8).scrub("").split(/\r\n|\r|\n/, 2).first.to_s
      CSV.parse_line(line)&.map { |name| name.to_s.strip } || []
    rescue CSV::MalformedCSVError
      nil
    ensure
      @file.rewind
    end

    def csv_like?
      @file.rewind
      sample = @file.read(SNIFF_BYTES).to_s.b
      return false if sample.empty? || sample.include?("\x00".b)

      sample = sample.delete_prefix("\xEF\xBB\xBF".b)
      # The sample may end in the middle of a multi-byte character.
      (0..3).any? do |trim|
        sample.byteslice(0, sample.bytesize - trim).force_encoding(Encoding::UTF_8).valid_encoding?
      end
    ensure
      @file.rewind
    end

    def format_size(bytes)
      bytes >= 1024 * 1024 ? "#{(bytes / 1024.0 / 1024).round(1).to_s.sub(/\.0\z/, '')} MB" : "#{bytes} bytes"
    end
  end
end
