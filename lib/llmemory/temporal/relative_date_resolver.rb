# frozen_string_literal: true

module Llmemory
  module Temporal
    class RelativeDateResolver
      def resolve(content, reference_time:)
        text = content.to_s
        anchor = Llmemory.parse_occurred_at(reference_time)&.utc
        return { event_date: nil, content: text } unless anchor

        anchor_day = utc_date(anchor)
        date = resolve_date(text, anchor_day)
        enriched = annotate_month_day(text, anchor_day)
        enriched = enrich_content(enriched, date, text.downcase) if date
        return { event_date: nil, content: enriched } unless date

        { event_date: date.strftime("%Y-%m-%d"), content: enriched }
      end

      private

      def utc_date(time)
        Date.new(time.utc.year, time.utc.month, time.utc.day)
      end

      def resolve_date(text, anchor_day)
        down = text.downcase
        day = anchor_day

        return day - 1 if down.match?(/\b(yesterday|ayer)\b/)
        return day if down.match?(/\b(today|hoy)\b/)
        return day + 1 if down.match?(/\b(tomorrow|mañana|manana)\b/)

        if (m = down.match(/\b(\d+)\s+days?\s+ago\b/))
          return day - m[1].to_i
        end
        if (m = down.match(/\b(\d+)\s+weeks?\s+ago\b/))
          return day - (m[1].to_i * 7)
        end

        return beginning_of_week(day) if down.match?(/\b(this week|esta semana)\b/)
        return beginning_of_month(day) if down.match?(/\b(this month|este mes)\b/)
        return beginning_of_year(day) if down.match?(/\b(this year|este año|este ano)\b/)
        return day - 7 if down.match?(/\b(last week|la semana pasada)\b/)
        return beginning_of_month(day - 30) if down.match?(/\b(last month|el mes pasado)\b/)
        return Date.new(day.year - 1, 1, 1) if down.match?(/\b(last year|el año pasado|el ano pasado)\b/)
        return Date.new(day.year + 1, 1, 1) if down.match?(/\bnext year\b/)
        return Date.new(day.year, day.month + 1, 1) if down.match?(/\bnext month\b/) && day.month < 12
        return Date.new(day.year + 1, 1, 1) if down.match?(/\bnext month\b/) && day.month == 12

        weekday = resolve_weekday_phrase(down, day)
        return weekday if weekday

        month_day = resolve_month_day(down, day)
        return month_day if month_day

        nil
      end

      MONTHS = {
        "january" => 1, "february" => 2, "march" => 3, "april" => 4,
        "may" => 5, "june" => 6, "july" => 7, "august" => 8,
        "september" => 9, "october" => 10, "november" => 11, "december" => 12
      }.freeze

      def resolve_month_day(down, anchor_day)
        return nil if down.match?(/\b(?:19|20)\d{2}\b/)

        match = down.match(/\b(#{MONTHS.keys.join("|")})\s+(\d{1,2})(?:st|nd|rd|th)?\b/)
        return nil unless match

        day_n = match[2].to_i
        return nil unless day_n.between?(1, 31)

        Date.new(anchor_day.year, MONTHS.fetch(match[1]), day_n)
      rescue Date::Error
        nil
      end

      def beginning_of_week(date)
        date - ((date.wday + 6) % 7)
      end

      def beginning_of_month(date)
        Date.new(date.year, date.month, 1)
      end

      def beginning_of_year(date)
        Date.new(date.year, 1, 1)
      end

      def enrich_content(original, date, down)
        return original if original.match?(/\(on \d/i) || original.match?(/\(\d{4}\)/)

        if down.match?(/\blast year\b/)
          return original.sub(/\blast year\b/i, "last year (#{date.year})")
        end
        if down.match?(/\bthis month\b/)
          return original.sub(/\bthis month\b/i, "this month (#{date.strftime('%B %Y')})")
        end
        if down.match?(/\bnext month\b/)
          return original.sub(/\bnext month\b/i, "next month (#{date.strftime('%B %Y')})")
        end
        if down.match?(/\blast week\b/)
          human = date.strftime("%-d %b %Y")
          return original.sub(/\blast week\b/i, "last week (#{human})")
        end

        human = date.strftime("%-d %b %Y")
        "#{original} (on #{human})"
      end

      def annotate_month_day(text, anchor_day)
        month_day = resolve_month_day(text.downcase, anchor_day)
        return text unless month_day

        iso = month_day.strftime("%Y-%m-%d")
        return text if text.include?(iso)

        text.sub(/\b((?:#{MONTHS.keys.join("|")})\s+\d{1,2}(?:st|nd|rd|th)?)\b/i) do
          "#{Regexp.last_match(1)} (#{iso})"
        end
      end

      def resolve_weekday_phrase(down, anchor_day)
        names = {
          "monday" => 1, "tuesday" => 2, "wednesday" => 3, "thursday" => 4,
          "friday" => 5, "saturday" => 6, "sunday" => 0,
          "lunes" => 1, "martes" => 2, "miércoles" => 3, "miercoles" => 3,
          "jueves" => 4, "viernes" => 5, "sábado" => 6, "sabado" => 6, "domingo" => 0
        }
        names.each do |name, wday|
          next unless down.match?(/\b(last|past)\s+#{name}\b/)

          delta = (anchor_day.wday - wday) % 7
          delta = 7 if delta.zero?
          return anchor_day - delta
        end
        nil
      end
    end
  end
end
