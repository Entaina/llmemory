# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Authentication do
  let(:inner_app) { ->(env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] } }
  let(:token) { "secret_token_123" }

  describe "when no token is configured" do
    subject { described_class.new(inner_app, token: nil) }

    it "passes requests through without authentication" do
      env = { "REQUEST_METHOD" => "GET" }
      status, _headers, _body = subject.call(env)

      expect(status).to eq(200)
    end
  end

  describe "when token is configured" do
    subject { described_class.new(inner_app, token: token) }

    context "with no credentials" do
      it "returns 401 Unauthorized" do
        env = { "REQUEST_METHOD" => "GET" }
        status, headers, body = subject.call(env)

        expect(status).to eq(401)
        expect(headers["Content-Type"]).to eq("application/json")
        expect(body.first).to include("Unauthorized")
      end
    end

    context "with valid Bearer token in Authorization header" do
      it "allows the request" do
        env = {
          "REQUEST_METHOD" => "GET",
          "HTTP_AUTHORIZATION" => "Bearer #{token}"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end
    end

    context "with valid token in Authorization header (no Bearer prefix)" do
      it "allows the request" do
        env = {
          "REQUEST_METHOD" => "GET",
          "HTTP_AUTHORIZATION" => token
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end
    end

    context "with invalid token in Authorization header" do
      it "returns 401 Unauthorized" do
        env = {
          "REQUEST_METHOD" => "GET",
          "HTTP_AUTHORIZATION" => "Bearer wrong_token"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(401)
      end
    end

    context "with valid token in query string" do
      it "allows the request" do
        env = {
          "REQUEST_METHOD" => "GET",
          "QUERY_STRING" => "token=#{token}"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end
    end

    context "with valid token in query string with other params" do
      it "allows the request" do
        env = {
          "REQUEST_METHOD" => "GET",
          "QUERY_STRING" => "foo=bar&token=#{token}&baz=qux"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end
    end

    context "with invalid token in query string" do
      it "returns 401 Unauthorized" do
        env = {
          "REQUEST_METHOD" => "GET",
          "QUERY_STRING" => "token=wrong_token"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(401)
      end
    end

    context "with case-insensitive Bearer prefix" do
      it "allows the request with lowercase bearer" do
        env = {
          "REQUEST_METHOD" => "GET",
          "HTTP_AUTHORIZATION" => "bearer #{token}"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end

      it "allows the request with mixed case Bearer" do
        env = {
          "REQUEST_METHOD" => "GET",
          "HTTP_AUTHORIZATION" => "BEARER #{token}"
        }
        status, _headers, _body = subject.call(env)

        expect(status).to eq(200)
      end
    end
  end

  describe "timing attack protection" do
    subject { described_class.new(inner_app, token: token) }

    it "uses constant-time comparison" do
      # This test verifies the secure_compare method exists and works
      # Actual timing attack testing would require more sophisticated benchmarking
      auth = subject

      # Access the private method for testing
      expect(auth.send(:secure_compare, "abc", "abc")).to be true
      expect(auth.send(:secure_compare, "abc", "def")).to be false
      expect(auth.send(:secure_compare, "abc", "ab")).to be false
      expect(auth.send(:secure_compare, nil, "abc")).to be false
      expect(auth.send(:secure_compare, "abc", nil)).to be false
    end
  end

  describe "with MCP_TOKEN environment variable" do
    around do |example|
      original = ENV["MCP_TOKEN"]
      ENV["MCP_TOKEN"] = "env_token_456"
      example.run
      ENV["MCP_TOKEN"] = original
    end

    it "uses token from environment when not explicitly provided" do
      auth = described_class.new(inner_app)

      env = {
        "REQUEST_METHOD" => "GET",
        "HTTP_AUTHORIZATION" => "Bearer env_token_456"
      }
      status, _headers, _body = auth.call(env)

      expect(status).to eq(200)
    end

    it "rejects requests with wrong token" do
      auth = described_class.new(inner_app)

      env = {
        "REQUEST_METHOD" => "GET",
        "HTTP_AUTHORIZATION" => "Bearer wrong_token"
      }
      status, _headers, _body = auth.call(env)

      expect(status).to eq(401)
    end
  end
end
