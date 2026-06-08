# frozen_string_literal: true

require_relative "resource"
require_relative "item"
require_relative "category"
require_relative "storage"
require_relative "../../noise_filter"
require_relative "../../memory_module"

module Llmemory
  module LongTerm
    module FileBased
      class Memory
        include Llmemory::MemoryModule

        def initialize(user_id:, storage: nil, llm: nil, extractor: nil)
          @user_id = user_id
          @storage = storage || Storages.build
          @llm = llm || Llmemory::LLM.client
          @extractor = extractor || Llmemory::Extractors::FactExtractor.new(llm: @llm)
        end

        def memorize(conversation_text)
          text = Llmemory.configuration.noise_filter_enabled ? NoiseFilter.filter?(conversation_text) : conversation_text.to_s
          return true if text.strip.empty?

          resource_id = save_resource(text)
          append_to_daily_log(text) if Llmemory.configuration.daily_logs_enabled && @storage.respond_to?(:save_daily_log_entry)
          items = @extractor.extract_items(text)
          updates_by_category = {}

          items.each do |item|
            content = item.is_a?(Hash) ? (item["content"] || item[:content]) : item.to_s
            importance = (item["importance"] || item[:importance] || 0.7).to_f
            cat = @extractor.classify_item(content)
            updates_by_category[cat] ||= []
            updates_by_category[cat] << content.to_s
            save_item(category: cat, item: item, source_resource_id: resource_id, importance: importance)
          end

          updates_by_category.each do |category, new_memories|
            existing_summary = @storage.load_category(@user_id, category)
            updated_summary = @extractor.evolve_summary(existing: existing_summary, new_memories: new_memories)
            @storage.save_category(@user_id, category, updated_summary)
          end

          true
        end

        def retrieve(query)
          retrieval = Retrieval.new(user_id: @user_id, storage: @storage, llm: @llm)
          retrieval.retrieve(query)
        end

        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          items = @storage.search_items(uid, query)
          resources = @storage.search_resources(uid, query)
          daily_logs = load_daily_logs_for_retrieval(uid) if Llmemory.configuration.daily_logs_enabled && @storage.respond_to?(:load_daily_logs)
          category_summaries = load_category_summaries_as_candidates(uid, query)
          out = []

          category_summaries.each do |c|
            out << c.merge(evergreen: true)
          end

          items.first(top_k).each do |i|
            out << {
              id: i[:id] || i["id"],
              text: i[:content] || i["content"],
              timestamp: i[:created_at] || i["created_at"],
              score: 1.0,
              importance: (i[:importance] || i["importance"] || 1.0).to_f,
              evergreen: i[:evergreen] || i["evergreen"]
            }
          end
          resources.first([top_k - out.size, 0].max).each do |r|
            out << {
              id: r[:id] || r["id"],
              text: r[:text] || r["text"],
              timestamp: r[:created_at] || r["created_at"],
              score: 0.9
            }
          end
          if daily_logs
            daily_logs.each do |log|
              out << { text: log[:content], timestamp: log[:date].to_time, score: 0.85 }
            end
          end
          out
        end

        # Stores a single fact produced outside the extraction flow (e.g. by
        # reflection over episodes), preserving caller-supplied provenance so the
        # insight remains traceable to its source. Returns the item id.
        def remember_fact(content:, category: "general", importance: 0.6, provenance: nil)
          return nil if content.to_s.strip.empty?
          @storage.save_item(
            @user_id,
            category: category.to_s,
            content: content.to_s,
            source_resource_id: nil,
            importance: importance,
            provenance: provenance
          )
        end

        # --- MemoryModule uniform interface ---

        def write(payload, **_meta)
          result = nil
          Llmemory::Instrumentation.instrument(:memory_write, memory_type: "file_based", user_id: @user_id) do
            result = memorize(payload)
          end
          result
        end

        def list(user_id: nil, limit: nil, offset: nil)
          @storage.list_items(user_id: user_id || @user_id, limit: limit, offset: offset)
        end

        def stats(user_id: nil)
          { items: @storage.count_items(user_id: user_id || @user_id) }
        end

        # Removes items/resources by id and records the removal in the audit log.
        # Note: file-based storages currently implement `archive_*` as physical
        # removal — `mode: :soft` and `mode: :hard` are functionally equivalent
        # here. Kept for API uniformity.
        def forget(ids:, reason: nil, mode: :soft)
          requested = Array(ids).map(&:to_s)
          existing = (@storage.get_all_items(@user_id) + @storage.get_all_resources(@user_id))
            .map { |r| (r[:id] || r["id"]).to_s }
          removed = requested & existing
          @storage.archive_items(@user_id, removed)
          @storage.archive_resources(@user_id, removed)
          forget_log.record(@user_id, memory_type: "file_based", ids: removed, reason: reason)
          Llmemory::Instrumentation.instrument(:memory_forget, memory_type: "file_based", user_id: @user_id, count: removed.size, mode: mode)
          removed.size
        end

        attr_reader :storage, :user_id

        private

        def save_resource(text)
          @storage.save_resource(@user_id, text)
        end

        def save_item(category:, item:, source_resource_id:, importance: 0.7)
          content = item.is_a?(Hash) ? item["content"] || item[:content] : item.to_s
          provenance = Llmemory::Provenance.from_resource(
            source_resource_id, method: "fact_extraction", confidence: importance
          )
          @storage.save_item(@user_id, category: category, content: content, source_resource_id: source_resource_id, importance: importance, provenance: provenance)
        end

        def append_to_daily_log(conversation_text)
          summary = conversation_text.length > 500 ? "#{conversation_text[0..500]}..." : conversation_text
          @storage.save_daily_log_entry(@user_id, Date.today, summary)
        end

        def load_daily_logs_for_retrieval(user_id)
          today = Date.today
          yesterday = today - 1
          logs = @storage.load_daily_logs(user_id, from_date: yesterday, to_date: today)
          logs.map { |l| { date: l[:date], content: "[#{l[:date]}] #{l[:content]}" } }
        end

        def load_category_summaries_as_candidates(user_id, query)
          return [] unless @storage.respond_to?(:list_categories)

          categories = @storage.list_categories(user_id)
          return [] if categories.empty?

          query_lower = query.to_s.downcase
          categories.filter_map do |cat|
            summary = @storage.load_category(user_id, cat)
            next if summary.to_s.strip.empty?
            next unless summary.to_s.downcase.include?(query_lower)

            { text: "[#{cat}] #{summary}", timestamp: Time.now, score: 0.95 }
          end
        end
      end
    end
  end
end
