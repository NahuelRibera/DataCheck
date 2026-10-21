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
