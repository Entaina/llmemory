# frozen_string_literal: true

require_relative "contract_spec"

require "llmemory/zero_mem/storages/postgres"

RSpec.describe Llmemory::ZeroMem::Storages::PostgresStorage,
               skip: ENV["DATABASE_URL"].to_s.empty? ? "DATABASE_URL not set" : false do
  include_examples "zero_mem trace storage contract", lambda {
    described_class.new(database_url: ENV["DATABASE_URL"], cipher: Llmemory::Crypto::NullCipher.new)
  }
end
