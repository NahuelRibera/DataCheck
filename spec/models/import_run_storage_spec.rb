require "rails_helper"

RSpec.describe "ImportRun file storage", type: :model do
  it "stores files under storage/test, not storage/ shared with development" do
    run = create(:import_run)
    expect(run.storage_dir.to_s).to include("/storage/test/import_runs/")
  end

  describe "#save_source_csv!" do
    after { FileUtils.rm_rf(run.storage_dir) }

    let(:run) { create(:import_run) }
    # UTF-8 BOM + CRLF, larger than several copy chunks
    let(:content) do
      "\xEF\xBB\xBFexternal_id,name\r\n".b + ("E0001,Synthetic Person\r\n" * 20_000).b
    end

    it "stores a byte-identical copy in the environment-scoped storage_dir" do
      run.save_source_csv!(StringIO.new(content.dup))

      expect(run.source_csv_path.dirname).to eq(run.storage_dir)
      expect(File.binread(run.source_csv_path)).to eq(content)
    end

    it "copies in chunks and never reads the whole IO at once" do
      io = StringIO.new(content.dup)
      lengths = []
      allow(io).to receive(:read).and_wrap_original do |original, *args|
        lengths << args.first
        original.call(*args)
      end
      allow(io).to receive(:readpartial).and_wrap_original do |original, *args|
        lengths << args.first
        original.call(*args)
      end

      run.save_source_csv!(io)

      expect(lengths.size).to be > 1
      expect(lengths).to all(be_a(Integer))
      expect(File.binread(run.source_csv_path)).to eq(content)
    end
  end
end

RSpec.describe "ImportRun file permissions", type: :model do
  let(:run) { create(:import_run) }

  after { FileUtils.rm_rf(run.storage_dir) }

  def mode_of(path) = File.stat(path).mode & 0o777

  it "creates the directory 0700 and source.csv 0600 under a permissive umask" do
    old = File.umask(0o000)
    begin
      run.save_source_csv!(StringIO.new("external_id\nE1\n"))
    ensure
      File.umask(old)
    end

    expect(mode_of(run.storage_dir)).to eq(0o700)
    expect(mode_of(run.source_csv_path)).to eq(0o600)
  end

  it "tightens a pre-existing permissive directory and file" do
    FileUtils.mkdir_p(run.storage_dir)
    File.chmod(0o755, run.storage_dir)
    File.write(run.source_csv_path, "x")
    File.chmod(0o644, run.source_csv_path)

    run.save_source_csv!(StringIO.new("external_id\nE1\n"))

    expect(mode_of(run.storage_dir)).to eq(0o700)
    expect(mode_of(run.source_csv_path)).to eq(0o600)
  end

  it "keeps normalized.csv 0600 after preflight, even under a permissive umask" do
    old = File.umask(0o000)
    begin
      run.save_source_csv!(StringIO.new("external_id\nE1\n"))
      Imports::PreflightService.new(run).call
    ensure
      File.umask(old)
    end

    expect(File.exist?(run.normalized_csv_path)).to be(true)
    expect(mode_of(run.normalized_csv_path)).to eq(0o600)
    expect(mode_of(run.storage_dir)).to eq(0o700)
  end
end
