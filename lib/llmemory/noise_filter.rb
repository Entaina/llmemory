# frozen_string_literal: true

module Llmemory
  class NoiseFilter
    NO_REPLY_MARKER = "NO_REPLY"
    DEFAULT_MIN_CHARS = 10

    def initialize(min_chars: nil, enabled: true)
      @min_chars = min_chars || Llmemory.configuration.noise_filter_min_chars
      @enabled = enabled
    end

    def filter(conversation_text)
      return conversation_text.to_s unless @enabled

      lines = conversation_text.to_s.split("\n")
      seen = {}
      filtered = lines.select do |line|
        next false if line.strip.length < @min_chars
        next false if line.include?(NO_REPLY_MARKER)
        next false if seen[line.strip]

        seen[line.strip] = true
        true
      end

      filtered.join("\n").strip
    end

    def self.filter?(conversation_text)
      return conversation_text.to_s unless Llmemory.configuration.noise_filter_enabled

      new.filter(conversation_text)
    end
  end
end
