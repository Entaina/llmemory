# frozen_string_literal: true

require "json"
require "uri"
require "faraday"

module Llmemory
  module ZeroMem
    class SidecarClient
      MAX_TEXT_BYTES = 32_768

      def initialize(base_url:, timeout: 5, breaker: nil)
        @base_url = base_url.to_s.sub(%r{/\z}, "")
        @timeout = timeout.to_f
        @breaker = breaker || CircuitBreaker.new
        validate_host!
      end

      def get_json(path)
        raise StoreError, "sidecar circuit open" unless @breaker.allow_request?

        response = connection.get(path)
        unless response.success?
          @breaker.record_failure
          raise StoreError, "sidecar HTTP error: #{response.status}"
        end
        @breaker.record_success
        JSON.parse(response.body)
      rescue Faraday::Error
        @breaker.record_failure
        raise StoreError, "sidecar request failed"
      end

      def post_json(path, body)
        raise StoreError, "sidecar circuit open" unless @breaker.allow_request?

        text = body[:text].to_s
        if text.bytesize > MAX_TEXT_BYTES
          raise StoreError, "sidecar payload exceeds max text bytes (#{MAX_TEXT_BYTES})"
        end

        response = connection.post(path) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = body.to_json
        end
        unless response.success?
          @breaker.record_failure
          raise StoreError, "sidecar HTTP error: #{response.status}"
        end

        @breaker.record_success
        JSON.parse(response.body)
      rescue Faraday::Error
        @breaker.record_failure
        raise StoreError, "sidecar request failed"
      end

      def degraded?
        @breaker.open?
      end

      private

      def connection
        @connection ||= Faraday.new(url: @base_url, request: { timeout: @timeout, open_timeout: @timeout }) do |f|
          f.adapter Faraday.default_adapter
        end
      end

      def validate_host!
        return unless Llmemory.configuration.zero_mem_require_local_encoders

        uri = URI.parse(@base_url)
        host = uri.host.to_s
        allowed = %w[127.0.0.1 localhost ::1]
        return if allowed.include?(host)

        raise ConfigurationError, "zero_mem sidecar host must be loopback when require_local_encoders is enabled"
      end
    end
  end
end
