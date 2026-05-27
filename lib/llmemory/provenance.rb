# frozen_string_literal: true

require "time"

module Llmemory
  # Provenance records the lineage of a long-term memory item: where it came
  # from, how it was produced, and with what confidence. It is stored as a
  # plain JSON-safe Hash so it round-trips through every storage backend
  # (in-memory, JSON files, SQL columns, jsonb properties) without coupling.
  #
  # Shape: { sources: [{ type:, id: }], method:, confidence:, created_at: }
  #
  # `method` identifies the producing process (e.g. "fact_extraction",
  # "entity_relation_extraction", and in the future "reflection"), so a
  # semantic datum can always be traced back to its raw source.
  module Provenance
    module_function

    def build(method:, sources: [], confidence: nil, created_at: nil)
      {
        sources: Array(sources).filter_map { |s| normalize_source(s) },
        method: method&.to_s,
        confidence: confidence.nil? ? nil : confidence.to_f,
        created_at: normalize_time(created_at)
      }
    end

    # Convenience for the file-based path, where the raw text is persisted as a
    # Resource and referenced by id.
    def from_resource(resource_id, method:, confidence: nil, created_at: nil)
      sources = resource_id ? [{ type: "resource", id: resource_id }] : []
      build(method: method, sources: sources, confidence: confidence, created_at: created_at)
    end

    # Convenience for the graph-based path, which does not persist the raw text.
    # We record a stable fingerprint of the source instead of the document
    # itself, keeping lineage verifiable without exposing sensitive content.
    def from_text_fingerprint(text, method:, confidence: nil, created_at: nil)
      require "digest"
      sources = []
      unless text.to_s.strip.empty?
        sources = [{ type: "text_sha256", id: Digest::SHA256.hexdigest(text.to_s)[0, 16] }]
      end
      build(method: method, sources: sources, confidence: confidence, created_at: created_at)
    end

    def normalize_source(source)
      return nil if source.nil?
      if source.is_a?(Hash)
        type = source[:type] || source["type"]
        id = source[:id] || source["id"]
        return nil if id.nil?
        { type: type.nil? ? "unknown" : type.to_s, id: id }
      else
        { type: "unknown", id: source }
      end
    end

    def normalize_time(value)
      value ||= Time.now
      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end
  end
end
