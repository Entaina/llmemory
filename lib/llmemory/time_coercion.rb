# frozen_string_literal: true

require "time"

module Llmemory
  module TimeCoercion
    module_function

    def parse_occurred_at(value)
      return value if value.is_a?(Time)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.empty?

      Time.parse(str)
    rescue ArgumentError
      nil
    end

    def iso8601_or_string(value)
      t = parse_occurred_at(value)
      t ? t.utc.iso8601 : value.to_s.strip
    end
  end
end
