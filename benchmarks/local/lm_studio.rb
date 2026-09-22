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
        c.llm_temperature = ENV.fetch("LLMEMORY_LLM_TEMPERATURE", "0").to_f
        seed = ENV["LLMEMORY_LLM_SEED"]
        c.llm_seed = seed if seed && !seed.empty?
        c.summary_refresh_every = ENV.fetch("LLMEMORY_SUMMARY_REFRESH_EVERY", "1").to_i
        max_out = ENV["LLMEMORY_LLM_MAX_OUTPUT_TOKENS"] || ENV["LLMEMORY_BENCH_MAX_OUTPUT_TOKENS"]
        c.llm_max_output_tokens = max_out.to_i if max_out && !max_out.to_s.empty?
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
      if expected.to_s.empty?
        puts "OK models (#{ids.size} loaded)"
        return
      end
      unless ids.any? { |id| id == expected.to_s || id.include?(expected.to_s) }
        raise "LM Studio model #{expected.inspect} not loaded. Available: #{ids.join(', ')}"
      end

      puts "OK model listed: #{expected}"
      ping_chat_completion!
    end

    def ping_chat_completion!
      return if ENV["LLMEMORY_SKIP_CHAT_HEALTH_CHECK"] == "1"

      ping_timeout = ENV.fetch("LLMEMORY_CHAT_HEALTH_TIMEOUT", "60").to_i
      saved_timeout = Llmemory.configuration.llm_timeout_seconds
      saved_retries = Llmemory.configuration.llm_http_retries
      Llmemory.configuration.llm_timeout_seconds = ping_timeout
      Llmemory.configuration.llm_http_retries = 0

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client = Llmemory::LLM.client
      response = client.invoke("Reply with exactly: OK")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      content = response.respond_to?(:content) ? response.content.to_s.strip : response.to_s.strip
      if content.empty?
        raise "LM Studio chat completion returned empty body (model may be stuck loading)"
      end

      puts "OK chat completion in #{elapsed.round(2)}s (#{content[0, 40]})"
    rescue Llmemory::LLMError => e
      raise "LM Studio chat completion failed (consolidation uses this API): #{e.message}. " \
            "Restart LM Studio, confirm the model is loaded and not busy with another request."
    ensure
      Llmemory.configuration.llm_timeout_seconds = saved_timeout unless saved_timeout.nil?
      Llmemory.configuration.llm_http_retries = saved_retries unless saved_retries.nil?
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
