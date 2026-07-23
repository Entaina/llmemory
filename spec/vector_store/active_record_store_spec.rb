# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "Llmemory::VectorStore::ActiveRecordStore loading" do
  it "can be required directly" do
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      'require "llmemory/vector_store/active_record_store"'
    )

    expect(status).to be_success, stderr
  end
end
