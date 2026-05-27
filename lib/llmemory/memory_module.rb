# frozen_string_literal: true

module Llmemory
  # Uniform contract for queryable long-term memories (file-based, graph-based,
  # episodic). CoALA argues agents should be modular with standardized
  # abstractions; this mixin gives any memory store the same agent-facing
  # surface so frameworks can treat them polymorphically:
  #
  #   read(query, user_id:, limit:)  -> relevant entries (retrieval)
  #   write(payload, ...)            -> ingest into the store (learning)
  #   list(user_id:, limit:)         -> enumerate stored entries
  #   stats(user_id:)                -> counts and metadata
  #
  # `read` defaults to the de-facto `search_candidates` interface the retrieval
  # Engine already relies on. `write`, `list` and `stats` are implemented by each
  # including class over its native API.
  #
  # Deliberately excluded: session-state stores (Checkpoint, WorkingMemory) are a
  # different abstraction (K/V session state, not a retrievable corpus), and
  # deletion/forgetting semantics are deferred to a coherent unlearning API.
  module MemoryModule
    def read(query, user_id: nil, limit: 20)
      unless respond_to?(:search_candidates)
        raise NotImplementedError, "#{self.class} must implement #read or #search_candidates"
      end
      search_candidates(query, user_id: user_id, top_k: limit)
    end

    def write(*, **)
      raise NotImplementedError, "#{self.class} must implement #write"
    end

    def list(user_id: nil, limit: nil)
      raise NotImplementedError, "#{self.class} must implement #list"
    end

    def stats(user_id: nil)
      raise NotImplementedError, "#{self.class} must implement #stats"
    end

    # Removes entries by id (the same ids returned by #read) and records the
    # removal in a ForgetLog audit. Returns the number of entries removed.
    # Implemented by stores with a clear deletion model; others may not support
    # it (CoALA-style "unlearning" is understudied; deletion semantics differ).
    def forget(ids:, reason: nil)
      raise NotImplementedError, "#{self.class} does not support #forget"
    end

    # Shared audit trail for #forget. Lazily built; override or inject by setting
    # @forget_log if a specific backend/store is required.
    def forget_log
      @forget_log ||= Llmemory::ForgetLog.new
    end
  end
end
