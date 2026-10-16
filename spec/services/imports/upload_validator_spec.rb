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
        expect(described_class.error_for(upload("a" * 100))).to be_nil
      end
    end

    it "rejects a file one byte over the limit" do
      with_limit("100") do
        expect(described_class.error_for(upload("a" * 101))).to eq(
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
      text = ("a" * (described_class::SNIFF_BYTES - 1)) + "é"
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
        described_class.error_for(upload("a\x00b", filename: secret_name)),
        described_class.error_for(upload("", filename: secret_name))
      ]
      with_limit("2") { messages << described_class.error_for(upload("abc", filename: secret_name)) }

      expect(messages).to all(be_a(String))
      messages.each { |m| expect(m).not_to include("zq-payroll-xk", ".exe") }
    end
  end
end
