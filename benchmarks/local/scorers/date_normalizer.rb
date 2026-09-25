# frozen_string_literal: true

require "date"

module LocalBenchmark
  module Scorers
    module DateNormalizer
      MONTHS = {
        "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "may" => 5, "jun" => 6,
        "jul" => 7, "aug" => 8, "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12
      }.freeze

      module_function

      def normalize_text(text)
        s = text.to_s.downcase.strip
        s = normalize_iso_dates(s)
        s = normalize_human_dates(s)
        s.gsub(/\s+/, " ").strip
      end

      def normalize_iso_dates(text)
        text.gsub(/\b(\d{4})-(\d{2})-(\d{2})\b/) do
          y, m, d = ::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i, ::Regexp.last_match(3).to_i
          format_date(y, m, d)
        end
      end

      def normalize_human_dates(text)
        down = text.dup
        down.gsub!(/\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\s+(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{4})\b/i) do
          d = ::Regexp.last_match(1).to_i
          m = MONTHS[::Regexp.last_match(2).downcase[0, 3]]
          y = ::Regexp.last_match(3).to_i
          format_date(y, m, d)
        end
        down.gsub!(/\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{4})\b/i) do
          d = ::Regexp.last_match(1).to_i
          m = MONTHS[::Regexp.last_match(2).downcase[0, 3]]
          y = ::Regexp.last_match(3).to_i
          format_date(y, m, d)
        end
        down.gsub!(/\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2}),?\s+(\d{4})\b/i) do
          month_name = ::Regexp.last_match(1).downcase
          m = MONTHS[month_name[0, 3]]
          d = ::Regexp.last_match(2).to_i
          y = ::Regexp.last_match(3).to_i
          format_date(y, m, d)
        end
        down
      end

      def format_date(y, m, d)
        return "" unless m && d.positive? && y.positive?

        Date.new(y, m, d).strftime("%-d %b %Y").downcase
      rescue ArgumentError
        ""
      end

      MONTH_NAMES = {
        "jan" => "january", "feb" => "february", "mar" => "march", "apr" => "april",
        "may" => "may", "jun" => "june", "jul" => "july", "aug" => "august",
        "sep" => "september", "oct" => "october", "nov" => "november", "dec" => "december"
      }.freeze

      def calendar_mentioned?(text, gold)
        normalized_gold = normalize_text(gold)
        return false if normalized_gold.empty?

        normalized = normalize_text(text)
        return true if normalized.include?(normalized_gold)
        return true if quoted_core_mentioned?(text, gold)

        match = normalized_gold.match(/\A(\d{1,2}) ([a-z]{3}) (\d{4})\z/)
        return false unless match

        day = match[1]
        mon = match[2]
        month = MONTH_NAMES[mon]
        down = text.to_s.downcase
        down.match?(/\b#{Regexp.escape(month)}\s+#{day}\b/) || down.match?(/\b#{day}\s+#{mon}/)
      end

      def quoted_core_mentioned?(text, gold)
        normalized = normalize_text(text)
        extract_quoted_spans(gold).any? do |core|
          ncore = normalize_text(core)
          ncore.length >= 30 && normalized.include?(ncore)
        end
      end

      def extract_quoted_spans(gold)
        gold.to_s.scan(/['"]([^'"]{20,})['"]/).flatten
      end

      def numeric_days_match?(prediction, gold)
        pred_nums = prediction.to_s.scan(/\b(\d+)\s+days?\b/i).flatten.map(&:to_i)
        gold_nums = gold.to_s.scan(/\b(\d+)\s+days?\b/i).flatten.map(&:to_i)
        return false if pred_nums.empty? || gold_nums.empty?

        (pred_nums & gold_nums).any?
      end
    end
  end
end
