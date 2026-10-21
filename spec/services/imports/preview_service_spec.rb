require "rails_helper"

RSpec.describe Imports::PreviewService do
  let(:import_run) { create(:import_run, company: create(:company)) }
  let(:path) { import_run.source_csv_path }
  let(:payload) { { "columns" => [{ "name" => "salary" }], "preview_rows" => [{ "salary" => "***" }] } }
  let(:ok_status) { instance_double(Process::Status, success?: true) }
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "external_id\nE1\n")
    allow(Open3).to receive(:capture3).and_return([payload.to_json, "", ok_status])
  end

  after { FileUtils.rm_f(path) }

  it "starts the profiler once for two reads of an unchanged file" do
    expect(described_class.new(import_run).call).to eq(payload)
    expect(described_class.new(import_run).call).to eq(payload)
    expect(Open3).to have_received(:capture3).once
  end

  it "runs the profiler again after the source file is replaced" do
    described_class.new(import_run).call
    File.write(path, "external_id\nE1\nE2\n")
    described_class.new(import_run).call
    expect(Open3).to have_received(:capture3).twice
  end

  it "returns nil for a missing file without caching or calling the profiler" do
    FileUtils.rm_f(path)
    expect(described_class.new(import_run).call).to be_nil
    expect(Open3).not_to have_received(:capture3)
    expect(memory_store.instance_variable_get(:@data)).to be_empty
  end

  it "does not cache a failed profiler result" do
    failed = instance_double(Process::Status, success?: false, exitstatus: 1)
    allow(Open3).to receive(:capture3).and_return(["", "boom", failed], [payload.to_json, "", ok_status])
    expect(described_class.new(import_run).call).to be_nil
    expect(described_class.new(import_run).call).to eq(payload)
    expect(Open3).to have_received(:capture3).twice
  end

  it "does not cache a profiler error payload" do
    allow(Open3).to receive(:capture3).and_return([{ "error" => "bad" }.to_json, "", ok_status])
    expect(described_class.new(import_run).call).to be_nil
    expect(described_class.new(import_run).call).to be_nil
    expect(Open3).to have_received(:capture3).twice
  end
end
