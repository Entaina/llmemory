# frozen_string_literal: true

require_relative "contract_spec"

RSpec.describe Llmemory::ZeroMem::Storages::Memory do
  include_examples "zero_mem trace storage contract", -> { described_class.new }
end
