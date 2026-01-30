# frozen_string_literal: true

module Llmemory
  module Maintenance
    class Summarizer
      def initialize(storage, llm: nil)
        @storage = storage
        @llm = llm || Llmemory::LLM.client
      end

      def run_weekly(user_id, prune_after_days: nil)
        prune_after_days ||= Llmemory.configuration.prune_after_days
        old_items = @storage.get_items_older_than(user_id, days: 30)
        categories = group_by_category(old_items)

        categories.each do |category, items|
          next if items.empty?
          summary = create_summary(items)
          existing = @storage.load_category(user_id, category)
          updated = existing.to_s.empty? ? summary : "#{existing}\n\n## Archived summary\n#{summary}"
          @storage.save_category(user_id, category, updated)
          @storage.archive_items(user_id, items.map { |i| i[:id] })
        end

        prune_stale_items(user_id, prune_after_days)
        true
      end

      private

      def group_by_category(items)
        items.group_by { |i| i[:category] }
      end

      def create_summary(items)
        bullet_points = items.map { |i| "- #{i[:content]}" }.join("\n")
        return bullet_points if bullet_points.length < 500
        prompt = <<~PROMPT
          Summarize these memory items into a short markdown paragraph (max 200 words).
          Items:
          #{bullet_points}
          Return only the summary.
        PROMPT
        @llm.invoke(prompt.strip).to_s
      rescue Llmemory::LLMError
        bullet_points[0..500]
      end

      def prune_stale_items(user_id, days)
        old = @storage.get_items_older_than(user_id, days: days)
        return if old.empty?
        ids = old.map { |i| i[:id] }
        @storage.archive_items(user_id, ids)
      end
    end
  end
end
