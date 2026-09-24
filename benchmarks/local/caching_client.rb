# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module LocalBenchmark
  class CachingClient
    CACHE_ROOT = File.expand_path("cache", __dir__)

    def initialize(inner:, model: nil, cache_reader: false)
      @inner = inner
      @model = (model || Llmemory.configuration.llm_model || "unknown").to_s.gsub(%r{[/\\]}, "_")
      @cache_reader = cache_reader
    end

    def invoke(prompt)
      path = cache_path(prompt)
      if File.file?(path)
        body = JSON.parse(File.read(path))
        return build_response(body)
      end

      response = @inner.invoke(prompt)
      write_cache(path, response)
      response
    end

    def invoke_with_json_schema(prompt, json_schema)
      key = "#{prompt}\n---SCHEMA---\n#{JSON.generate(json_schema)}"
      path = cache_path(key)
      if File.file?(path)
        return JSON.parse(File.read(path))
      end

      parsed = @inner.invoke_with_json_schema(prompt, json_schema)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(parsed))
      parsed
    end

    def respond_to?(method, include_private = false)
      @inner.respond_to?(method, include_private) || super
    end

    def method_missing(method, ...)
      @inner.public_send(method, ...)
    end

    def self.wrap!(cache_reader: false)
      return Llmemory::LLM.client unless ENV["LLMEMORY_BENCH_CACHE"] == "1"

      new(inner: Llmemory::LLM.client, cache_reader: cache_reader)
    end

    private

    def cache_path(prompt)
      digest = Digest::SHA256.hexdigest(prompt.to_s)
      File.join(CACHE_ROOT, @model, "#{digest}.json")
    end

    def write_cache(path, response)
      FileUtils.mkdir_p(File.dirname(path))
      payload = if response.respond_to?(:content)
                  { "content" => response.content.to_s, "usage" => usage_hash(response) }
                else
                  { "content" => response.to_s }
                end
      File.write(path, JSON.pretty_generate(payload))
    end

    def usage_hash(response)
      u = response.usage
      return nil unless u

      {
        "input_tokens" => u.input_tokens,
        "output_tokens" => u.output_tokens,
        "total_tokens" => u.total_tokens
      }
    end

    def build_response(body)
      usage = body["usage"]
      u = if usage
            Llmemory::LLM::Usage.new(
              input_tokens: usage["input_tokens"],
              output_tokens: usage["output_tokens"],
              total_tokens: usage["total_tokens"]
            )
          end
      Llmemory::LLM::Response.new(body["content"].to_s, usage: u)
    end
  end
end
