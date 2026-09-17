# frozen_string_literal: true

require "json"

module LocalBenchmark
  module Scorers
    module ToolCall
      module_function

      def parse_tool_call(text)
        json = text.to_s[/\{.*\}/m]
        return nil unless json

        data = JSON.parse(json)
        {
          name: data["name"] || data["tool"],
          arguments: data["arguments"] || data["parameters"] || {}
        }
      rescue JSON::ParserError
        nil
      end

      def tool_accuracy(prediction, gold_name)
        parsed = parse_tool_call(prediction)
        return 0.0 unless parsed

        parsed[:name].to_s == gold_name.to_s ? 1.0 : 0.0
      end

      def param_f1(prediction, gold_arguments)
        parsed = parse_tool_call(prediction)
        return 0.0 unless parsed

        gold = gold_arguments.transform_keys(&:to_s).transform_values { |v| v.to_s.downcase.strip }
        pred = parsed[:arguments].transform_keys(&:to_s).transform_values { |v| v.to_s.downcase.strip }
        keys = (gold.keys + pred.keys).uniq
        return 0.0 if keys.empty?

        hits = keys.count { |k| pred[k] == gold[k] }
        hits.to_f / keys.size
      end
    end
  end
end
