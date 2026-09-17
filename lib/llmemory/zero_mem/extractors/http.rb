# frozen_string_literal: true

require "json"
require "faraday"
require_relative "../entity_extractor"

module Llmemory
  module ZeroMem
    module Extractors
      class Http < EntityExtractor
        def initialize(base_url:, timeout: 5, client: nil)
          @base_url = base_url.to_s.sub(%r{/\z}, "")
          @timeout = timeout
          @client = client
        end

        def extract(text)
          body = sidecar.post_json("/ner", { text: text.to_s })
          Array(body["entities"]).map do |ent|
            {
              text: ent["text"],
              normalized: ent["normalized"] || ent["text"].to_s.downcase,
              type: (ent["type"] || "entity").to_sym,
              start: ent["start"] || 0,
              end: ent["end"] || 0
            }
          end
        end

        def name
          "http"
        end

        def version
          health["version"] || "unknown"
        rescue StandardError
          "unknown"
        end

        def health
          sidecar.get_json("/health")
        rescue StoreError
          { "status" => "down" }
        end

        def degraded?
          sidecar.degraded?
        end

        private

        def sidecar
          @client ||= SidecarClient.new(base_url: @base_url, timeout: @timeout)
        end
      end
    end
  end
end
