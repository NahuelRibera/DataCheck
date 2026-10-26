require "rails_helper"
require "tempfile"

RSpec.describe Imports::UploadValidator do
  let(:default_max) { described_class::DEFAULT_MAX_BYTES }
  let(:secret_name) { "zq-payroll-xk.csv" }

  def upload(content, filename: "employees.csv")
    file = Tempfile.new(["upload", ".csv"], binmode: true)
    file.write(content)
    file.rewind
    uploads << file
    double("upload", original_filename: filename, size: content.bytesize).tap do |d|
      allow(d).to receive(:rewind) { file.rewind }
      allow(d).to receive(:read) { |n| file.read(n) }
      allow(d).to receive(:blank?).and_return(false)
    end
  end

  let(:uploads) { [] }
  after { uploads.each(&:close!) }

  let(:header) { described_class::REQUIRED_COLUMNS.join(",") }

  # A file with a valid header, padded with a comment-free data row to an exact size.
  def sized_file(bytes)
    "#{header}\n".ljust(bytes, "a")
  end

  def with_limit(value)
    original = ENV["IMPORT_MAX_UPLOAD_BYTES"]
    ENV["IMPORT_MAX_UPLOAD_BYTES"] = value
    yield
  ensure
    ENV["IMPORT_MAX_UPLOAD_BYTES"] = original
  end

  describe ".max_bytes" do
    it "uses the default when the variable is unset" do
      with_limit(nil) { expect(described_class.max_bytes).to eq(default_max) }
    end

    it "uses a valid positive value" do
      with_limit("1024") { expect(described_class.max_bytes).to eq(1024) }
    end

    %w[abc 12.5 0 -5 -1048576].push("", " ").each do |value|
      it "falls back to the default for #{value.inspect}" do
        with_limit(value) { expect(described_class.max_bytes).to eq(default_max) }
      end
    end
  end

  describe "#error" do
    it "accepts a file exactly at the limit" do
      with_limit("100") do
        expect(described_class.error_for(upload(sized_file(100)))).to be_nil
      end
    end

    it "rejects a file one byte over the limit" do
      with_limit("100") do
        expect(described_class.error_for(upload(sized_file(101)))).to eq(
          "The file is too large. The maximum upload size is 100 bytes."
        )
      end
    end

    it "rejects content with NUL bytes" do
      expect(described_class.error_for(upload("id,name\n1,a\x00b\n"))).to eq(
        "The file does not look like a CSV text file."
      )
    end

    it "rejects an empty file" do
      expect(described_class.error_for(upload(""))).to eq("The file does not look like a CSV text file.")
    end

    it "rejects a wrong extension" do
      expect(described_class.error_for(upload("a,b\n", filename: "data.txt"))).to eq(
        "The file must have a .csv extension."
      )
    end

    it "accepts a sample cut in the middle of a multi-byte character" do
      text = "#{header}\n" + ("a" * (described_class::SNIFF_BYTES - header.bytesize - 2)) + "é"
      expect(text.bytesize).to eq(described_class::SNIFF_BYTES + 1)
      expect(described_class.error_for(upload(text))).to be_nil
    end

    it "rejects invalid UTF-8 that is not a truncation" do
      expect(described_class.error_for(upload("a,b\n\xFF\xFE,x\n"))).to eq(
        "The file does not look like a CSV text file."
      )
    end

    it "never includes the client filename in any message" do
      messages = [
        described_class.error_for(upload("a,b\n", filename: "#{secret_name}.exe")),
        described_class.error_for(upload("a,b\n1,2\n", filename: secret_name)),
        described_class.error_for(upload("a\x00b", filename: secret_name)),
        described_class.error_for(upload("", filename: secret_name))
      ]
      with_limit("2") { messages << described_class.error_for(upload("abc", filename: secret_name)) }

      expect(messages).to all(be_a(String))
      messages.each { |m| expect(m).not_to include("zq-payroll-xk", ".exe") }
    end

    describe "header check" do
      let(:required) { described_class::REQUIRED_COLUMNS }

      it "accepts a valid header with extra optional columns" do
        expect(described_class.error_for(upload("#{header},email,status\nEMP-1,a,b,D,2024-01-01,1,x,y\n"))).to be_nil
      end

      it "accepts a header with a UTF-8 byte order mark" do
        expect(described_class.error_for(upload("\xEF\xBB\xBF#{header}\n".b))).to be_nil
      end

      it "accepts quoted names, surrounding spaces and CRLF line endings" do
        quoted = required.map { |c| %("  #{c} ") }.join(",")
        expect(described_class.error_for(upload("#{quoted}\r\nrow\r\n"))).to be_nil
      end

      it "accepts a header-only file without a trailing newline" do
        expect(described_class.error_for(upload(header))).to be_nil
      end

      it "lists every missing column in a stable order" do
        content = "external_id,email\nEMP-1,secret@example.com\n"
        expect(described_class.error_for(upload(content))).to eq(
          "The file is missing required columns: first_name, last_name, department_external_id, start_date, gross_salary."
        )
      end

      it "names a single missing column" do
        columns = (required - ["gross_salary"]).join(",")
        expect(described_class.error_for(upload("#{columns}\n"))).to eq(
          "The file is missing required columns: gross_salary."
        )
      end

      it "treats an empty first line as a header with no columns" do
        error = described_class.error_for(upload("\n#{header}\n"))
        expect(error).to eq("The file is missing required columns: #{required.join(', ')}.")
      end

      it "is case sensitive like the profiler" do
        expect(described_class.error_for(upload("#{header.upcase}\n"))).to start_with("The file is missing")
      end

      it "reports an unreadable header without echoing it" do
        error = described_class.error_for(upload(%(external_id,"unterminated secret-cell\n1,2\n)))
        expect(error).to eq("The header row could not be read. Check that the first line lists the column names.")
      end

      it "never includes cell values in the message" do
        error = described_class.error_for(upload("external_id,first_name\nzq-secret-1,zq-secret-2\n"))
        expect(error).not_to include("zq-secret")
      end
    end
  end

  describe "REQUIRED_COLUMNS" do
    it "matches the required columns of the Python profiler" do
      source = Rails.root.join("scripts/profile_import.py").read
      block = source[/^REQUIRED_COLUMNS\s*=\s*\{(.*?)\}/m, 1]
      expect(block).not_to be_nil
      python_columns = block.scan(/["']([^"']+)["']/).flatten

      expect(described_class::REQUIRED_COLUMNS).to match_array(python_columns)
    end
  end
end
