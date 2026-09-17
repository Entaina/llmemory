# frozen_string_literal: true

require_relative "adapters/fixtures"
require_relative "adapters/locomo"
require_relative "adapters/longmemeval"
require_relative "adapters/memory_agent_bench"
require_relative "adapters/locomo_plus"
require_relative "adapters/mem_syco"
require_relative "adapters/group_mem_bench"
require_relative "adapters/mem2act"
require_relative "adapters/memory_arena"

module LocalBenchmark
  module Registry
    BENCHES = {
      "fixtures" => Adapters::Fixtures,
      "locomo" => Adapters::LoCoMo,
      "longmemeval" => Adapters::LongMemEval,
      "memoryagentbench" => Adapters::MemoryAgentBench,
      "locomo_plus" => Adapters::LoCoMoPlus,
      "memsyco" => Adapters::MemSyco,
      "groupmembench" => Adapters::GroupMemBench,
      "mem2act" => Adapters::Mem2Act,
      "memory_arena" => Adapters::MemoryArena
    }.freeze

    module_function

    def fetch(name)
      key = name.to_s.downcase
      klass = BENCHES[key]
      raise ArgumentError, "Unknown bench #{name}. Known: #{BENCHES.keys.join(', ')}" unless klass

      klass
    end

    def build(name)
      fetch(name).new
    end
  end
end
