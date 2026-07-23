# frozen_string_literal: true

require "cgi"

module Llmemory
  module MCP
    # Rack middleware for token-based authentication
    # Validates requests against MCP_TOKEN environment variable
    class Authentication
      UNAUTHORIZED_RESPONSE = [
        401,
        { "Content-Type" => "application/json" },
        ['{"error":"Unauthorized: Invalid or missing token"}']
      ].freeze

      def initialize(app, token: nil)
        @app = app
        @token = token || ENV["MCP_TOKEN"]
      end

      def call(env)
        return @app.call(env) unless @token

        return UNAUTHORIZED_RESPONSE unless valid_token?(env)

        @app.call(env)
      end

      private

      def valid_token?(env)
        # Check Authorization header (Bearer token)
        auth_header = env["HTTP_AUTHORIZATION"]
        if auth_header
          # Support both "Bearer <token>" and plain "<token>"
          token = auth_header.sub(/\ABearer\s+/i, "")
          return true if secure_compare(token, @token)
        end

        # Check query string parameter
        query_string = env["QUERY_STRING"] || ""
        query_params = parse_query_string(query_string)
        if query_params["token"]
          return true if secure_compare(query_params["token"], @token)
        end

        false
      end

      def parse_query_string(query_string)
        query_string.split("&").each_with_object({}) do |pair, hash|
          key, value = pair.split("=", 2)
          next unless key

          hash[CGI.unescape(key)] = CGI.unescape(value.to_s)
        end
      end

      # Constant-time comparison to prevent timing attacks
      def secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false if a.bytesize != b.bytesize

        l = a.unpack("C*")
        r = b.unpack("C*")
        result = 0
        l.zip(r) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end
