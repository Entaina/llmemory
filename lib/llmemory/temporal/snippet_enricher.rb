# frozen_string_literal: true

require_relative "relative_date_resolver"

module Llmemory
  module Temporal
    module SnippetEnricher
      RELATIVE_PATTERNS = [
        /\blast year\b/i,
        /\bthis month\b/i,
        /\bnext month\b/i,
        /\blast week\b/i,
        /\bthis week\b/i,
        /\byesterday\b/i,
        /\btoday\b/i,
        /\btomorrow\b/i,
        /\bthree years ago\b/i,
        /\blast year\b/i
      ].freeze

      module_function

      def enrich(content, reference_time:, occurred_at_inferred: false)
        text = content.to_s
        return text if occurred_at_inferred
        return text unless reference_time
        return text unless RELATIVE_PATTERNS.any? { |re| text.match?(re) }

        resolver = RelativeDateResolver.new
        result = resolver.resolve(text, reference_time: reference_time)
        result[:content] || text
      end

      def timeline_deltas(items)
        dated = items.filter_map do |item|
          time = item[:occurred_at] || item[:timestamp] || item[:event_date]
          time = Llmemory.parse_occurred_at(time) unless time.is_a?(Time)
          next unless time

          { time: time, text: item[:text].to_s[0, 120], label: item[:trace_id] || item[:id] }
        end.sort_by { |r| r[:time] }

        lines = []
        dated.each_with_index do |row, idx|
          prefix = idx.zero? ? "1st" : (idx == 1 ? "2nd" : "#{idx + 1}th")
          label = row[:time].utc.strftime("%a %-d %b %Y")
          lines << "#{prefix}: #{label} — #{row[:text]}"
          next if idx.zero?

          delta = ((row[:time] - dated[idx - 1][:time]) / 86_400.0).round
          lines << "  Δ #{delta} days since previous"
        end
        lines
      end
    end
  end
end
