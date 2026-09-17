# frozen_string_literal: true

require "json"
require "yaml"
require "net/http"
require "uri"
require "llmemory"

module LocalBenchmark
  module LmStudio
    DEFAULT_BASE_URL = "http://127.0.0.1:1234/v1"
    MODELS_PATH = File.expand_path("models.yml", __dir__)

    module_function

    def profile_name
      ENV.fetch("LLMEMORY_BENCH_PROFILE", "default").to_s
    end

    def profile
      data = YAML.load_file(MODELS_PATH)
      name = profile_name
      prof = data.dig("profiles", name)
      raise ArgumentError, "Unknown LLMEMORY_BENCH_PROFILE=#{name}" unless prof

      prof.merge("name" => name)
    end

    def apply_profile!
      prof = profile
      Llmemory.configure do |c|
        c.llm_provider = :openai
        c.llm_base_url = ENV.fetch("LLMEMORY_LLM_BASE_URL", DEFAULT_BASE_URL)
        c.llm_api_key = ENV.fetch("LLMEMORY_LLM_API_KEY", "lm-studio")
        c.llm_model = ENV.fetch("LLMEMORY_LLM_MODEL", prof["llm_model"])
        c.llm_timeout_seconds = ENV.fetch("LLMEMORY_LLM_TIMEOUT", "600").to_i
        c.llm_http_retries = ENV.fetch("LLMEMORY_LLM_HTTP_RETRIES", "4").to_i
        c.long_term_type = :file_based
        c.episodic_vector_enabled = false
        c.procedural_vector_enabled = false
      end
      prof
    end

    def base_url
      Llmemory.configuration.llm_base_url || DEFAULT_BASE_URL
    end

    def health_check!(model: nil)
      return if ENV["LLMEMORY_SKIP_HEALTH_CHECK"] == "1"

      expected = model || Llmemory.configuration.llm_model
      root = base_url.to_s.sub(%r{/v1/?\z}, "")
      uri = URI.parse("#{root}/v1/models")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise "LM Studio health check failed: GET #{uri} -> #{response.code}"
      end

      body = JSON.parse(response.body)
      ids = Array(body["data"]).map { |m| m["id"].to_s }
      return if expected.to_s.empty?
      return if ids.any? { |id| id == expected.to_s || id.include?(expected.to_s) }

      raise "LM Studio model #{expected.inspect} not loaded. Available: #{ids.join(', ')}"
    end

    def metadata
      prof = profile
      {
        profile: prof["name"],
        llm_model: Llmemory.configuration.llm_model,
        quant: prof["quant"],
        ctx: prof["ctx"],
        llm_base_url: base_url
      }
    end
  end
end
