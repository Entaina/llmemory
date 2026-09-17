# frozen_string_literal: true

module Llmemory
  module ZeroMem
    module Storages
      class LlmemoryTrace < ::ActiveRecord::Base
        self.table_name = "llmemory_traces"
        self.primary_key = "id"
      end

      class LlmemoryTraceStateLink < ::ActiveRecord::Base
        self.table_name = "llmemory_trace_state_links"
      end

      class LlmemoryTraceUnit < ::ActiveRecord::Base
        self.table_name = "llmemory_trace_units"
        self.primary_key = "id"
      end
    end
  end
end
