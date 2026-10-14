module Imports
  # Checks an uploaded file before it is stored or handed to the profiler.
  # Messages never include file contents or the client-supplied filename.
  class UploadValidator
    DEFAULT_MAX_BYTES = 20 * 1024 * 1024
    SNIFF_BYTES = 8192

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

      "The file does not look like a CSV text file." unless csv_like?
    end

    private

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
