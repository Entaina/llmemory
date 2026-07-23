# frozen_string_literal: true

require "json"

module Llmemory
  module LLM
    module HttpClient
      RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

      private

      def http_timeout
        (Llmemory.configuration.llm_timeout_seconds || 60).to_i
      end

      def http_open_timeout
        (Llmemory.configuration.llm_open_timeout_seconds || 10).to_i
      end

      def build_faraday_connection(url)
        Faraday.new(url: url) do |f|
          f.request :json
          f.response :json
          f.options.timeout = http_timeout
          f.options.open_timeout = http_open_timeout
          f.adapter Faraday.default_adapter
        end
      end

      def post_with_resilience(connection, path, &block)
        attempts = 0
        max_attempts = (Llmemory.configuration.llm_http_retries || 2).to_i + 1

        loop do
          begin
            response = connection.post(path, &block)
            if RETRYABLE_STATUSES.include?(response.status) && attempts < max_attempts - 1
              attempts += 1
              sleep(0.5 * (2**(attempts - 1)))
              next
            end
            return response
          rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
            attempts += 1
            raise Llmemory::LLMError, "HTTP request failed: #{e.message}" if attempts >= max_attempts

            sleep(0.5 * (2**(attempts - 1)))
          rescue Faraday::Error => e
            raise Llmemory::LLMError, "HTTP request failed: #{e.message}"
          end
        end
      end
    end
  end
end
