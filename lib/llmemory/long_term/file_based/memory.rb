# frozen_string_literal: true

require_relative "resource"
require_relative "item"
require_relative "category"
require_relative "storage"
require_relative "../../noise_filter"
require_relative "../../memory_module"
require_relative "../../consolidation/filter"

module Llmemory
  module LongTerm
    module FileBased
      class Memory
        include Llmemory::MemoryModule

        def initialize(user_id:, storage: nil, llm: nil, extractor: nil, forget_log_store: nil)
          @user_id = user_id
          @storage = storage || Storages.build
          @forget_log_store = forget_log_store
          @llm = llm || Llmemory::LLM.client
          @extractor = extractor || Llmemory::Extractors::FactExtractor.new(llm: @llm)
          @consolidation_count = 0
        end

        def known_facts_for(conversation_text, limit: 12)
          tokens = Llmemory::Tokenizer.content_tokens(conversation_text.to_s)
          return [] if tokens.empty?

          hits = @storage.search_items(@user_id, tokens.first(8).join(" "))
          hits.first(limit * 2).filter_map do |item|
            content = (item[:content] || item["content"]).to_s
            next if content.empty?

            subj = item[:subject] || item["subject"]
            pred = item[:predicate] || item["predicate"]
            if subj.to_s.strip.empty? || pred.to_s.strip.empty?
              content
            else
              "#{subj} #{pred}: #{content}"
            end
          end.uniq.first(limit)
        end

        def memorize(conversation_text, reference_time: nil, source_trace_ids: nil, source_traces: nil, known_facts: nil)
          text = Llmemory.configuration.noise_filter_enabled ? NoiseFilter.filter?(conversation_text) : conversation_text.to_s
          text = bench_truncate_extract_text(text)
          return true if text.strip.empty?

          @consolidation_count += 1
          bench_memorize_trace("start chars=#{text.length}") if bench_trace?

          traces = normalize_source_traces(source_traces, source_trace_ids)
          resource_id = bench_trace_measure("save_resource") { save_resource(text, occurred_at: reference_time) }
          append_to_daily_log(text) if Llmemory.configuration.daily_logs_enabled && @storage.respond_to?(:save_daily_log_entry)
          known = Array(known_facts) + known_facts_for(text)
          known = known.uniq
          items = bench_trace_measure("extract_items") do
            @extractor.extract_items(text, reference_time: reference_time, known_facts: known)
          end
          contents = items.map { |item| item.is_a?(Hash) ? (item["content"] || item[:content]).to_s : item.to_s }
          classifications = bench_trace_measure("classify_items(#{contents.size})") do
            classifications_for_items(items, contents)
          end
          items = Consolidation::Filter.apply_items(items, classifications)
          updates_by_category = {}

          items.each do |item|
            content = item.is_a?(Hash) ? (item["content"] || item[:content]) : item.to_s
            importance = (item["importance"] || item[:importance] || 0.7).to_f
            cat = item_category(item, classifications, content)
            volatile = item[:volatile] == true
            updates_by_category[cat] ||= []
            updates_by_category[cat] << content.to_s
            save_item(
              category: cat,
              item: item,
              source_resource_id: resource_id,
              importance: importance,
              volatile: volatile,
              occurred_at: reference_time,
              source_traces: traces
            )
          end

          refresh_every = Llmemory.configuration.summary_refresh_every.to_i
          refresh_every = 1 if refresh_every <= 0
          if refresh_every <= 1 || (@consolidation_count % refresh_every).zero?
            updates_by_category.each do |category, new_memories|
              existing_summary = @storage.load_category(@user_id, category)
              updated_summary = bench_trace_measure("evolve_summary(#{category})") do
                @extractor.evolve_summary(existing: existing_summary, new_memories: new_memories)
              end
              @storage.save_category(@user_id, category, updated_summary)
            end
          else
            bench_memorize_trace("skip evolve_summary (refresh_every=#{refresh_every})") if bench_trace?
          end

          bench_memorize_trace("done items=#{items.size}") if bench_trace?
          true
        end

        def retrieve(query)
          candidates = search_candidates(query, top_k: 20)
          Llmemory::Retrieval::ContextAssembler.new.assemble(candidates)
        end

        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          expanded_k = list_style_query?(query) ? [top_k * 2, 40].min : top_k
          item_pool = list_style_query?(query) ? top_k * 6 : top_k * 3
          items = @storage.search_items(uid, expanded_query_for_lists(query))
          resources = @storage.search_resources(uid, query)
          daily_logs = load_daily_logs_for_retrieval(uid) if Llmemory.configuration.daily_logs_enabled && @storage.respond_to?(:load_daily_logs)
          category_summaries = load_category_summaries_as_candidates(uid, query)
          bm25 = Llmemory::Retrieval::Bm25Scorer.new
          out = []

          category_summaries.each do |c|
            out << c.merge(evergreen: true, kind: :summary)
          end

          item_rows = grouped_item_candidates(items.first(item_pool)).first(expanded_k).map do |i|
            prov = i[:provenance] || i["provenance"]
            {
              id: i[:id] || i["id"],
              text: i[:content] || i["content"],
              timestamp: item_timestamp(i),
              score: 1.0,
              importance: (i[:importance] || i["importance"] || 1.0).to_f,
              evergreen: i[:evergreen] || i["evergreen"],
              volatile: Consolidation::Filter.volatile_marked?(prov),
              provenance: prov,
              kind: :fact,
              event_date: i[:event_date] || i["event_date"]
            }
          end
          scored_items = bm25.score_candidates(query, item_rows)
          scored_items.sort_by { |c| -(c[:normalized_bm25] || 0) }.each { |row| out << row }

          resource_rows = resources.first([top_k, 0].max).map do |r|
            {
              id: r[:id] || r["id"],
              text: r[:text] || r["text"],
              timestamp: r[:created_at] || r["created_at"],
              score: 0.9,
              kind: :resource
            }
          end
          bm25.score_candidates(query, resource_rows).sort_by { |c| -(c[:normalized_bm25] || 0) }.first([top_k - out.size, 0].max).each do |row|
            out << row.merge(score: row[:normalized_bm25].to_f.clamp(0.0, 1.0))
          end
          if daily_logs
            daily_logs.each do |log|
              out << { text: log[:content], timestamp: log[:date].to_time, score: 0.85, kind: :daily_log }
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

        def save_resource(text, occurred_at: nil)
          @storage.save_resource(@user_id, text, occurred_at: occurred_at)
        end

        def save_item(category:, item:, source_resource_id:, importance: 0.7, volatile: false, occurred_at: nil,
                      source_traces: [])
          content = item.is_a?(Hash) ? item["content"] || item[:content] : item.to_s
          provenance = Llmemory::Provenance.from_resource(
            source_resource_id, method: "fact_extraction", confidence: importance, created_at: occurred_at
          )
          trace_ids = Consolidation::TraceAttribution.trace_ids_for_fact(content, source_traces)
          provenance = Consolidation::TraceAttribution.merge_trace_sources(provenance, trace_ids) if trace_ids.any?
          provenance = Consolidation::Filter.volatile_provenance(provenance) if volatile
          extra = {}
          if item.is_a?(Hash)
            subj = item["subject"] || item[:subject]
            pred = item["predicate"] || item[:predicate]
            extra[:subject] = subj if subj && !subj.to_s.strip.empty?
            extra[:predicate] = pred if pred && !pred.to_s.strip.empty?
          end
          @storage.save_item(
            @user_id,
            category: category,
            content: content,
            source_resource_id: source_resource_id,
            importance: importance,
            provenance: provenance,
            occurred_at: occurred_at,
            event_date: item_event_date(item, occurred_at),
            **extra
          )
        end

        def item_event_date(item, reference_time)
          return nil unless item.is_a?(Hash)

          raw = item["event_date"] || item[:event_date]
          return nil if raw.nil? || raw.to_s.strip.empty?

          Llmemory.parse_occurred_at(raw) || reference_time
        end

        def classifications_for_items(items, contents)
          if bench_trace? && ENV["LLMEMORY_BENCH_FAST"] == "1"
            return contents.each_with_object({}) { |content, acc| acc[content] = "general" }
          end

          from_items = contents.each_with_object({}) do |content, acc|
            item = items.find { |i| (i["content"] || i[:content]).to_s == content }
            cat = item && (item["category"] || item[:category]).to_s.strip.downcase.gsub(/\s+/, "_")
            acc[content] = cat unless cat.nil? || cat.empty?
          end
          missing = contents.reject { |c| from_items.key?(c) }
          return from_items if missing.empty?

          from_items.merge(@extractor.classify_items(missing))
        end

        def item_category(item, classifications, content)
          inline = item.is_a?(Hash) && (item["category"] || item[:category]).to_s.strip
          cat = inline.to_s.downcase.gsub(/\s+/, "_")
          return cat unless cat.empty?

          classifications[content] || @extractor.classify_item(content)
        end

        def list_style_query?(query)
          q = query.to_s.downcase
          return true if q.match?(/\b(activities|places|locations|hobbies|likes|camped|visited|enjoy)\b/)
          return true if q.match?(/\bwhat do .+ like\b/)

          q.match?(/\b(list|name all|what are the)\b/)
        end

        def expanded_query_for_lists(query)
          q = query.to_s
          return q unless list_style_query?(q)

          synonyms = {
            "like" => "prefer enjoys favorite",
            "camped" => "camp camping",
            "activities" => "activity hobby"
          }
          extra = synonyms.filter_map { |needle, add| add if q.downcase.include?(needle) }.join(" ")
          extra.empty? ? q : "#{q} #{extra}"
        end

        def grouped_item_candidates(items)
          buckets = Hash.new { |h, k| h[k] = [] }
          singles = []
          items.each do |item|
            subj = item[:subject] || item["subject"]
            pred = item[:predicate] || item["predicate"]
            if subj.to_s.strip.empty? || pred.to_s.strip.empty?
              singles << item
              next
            end
            buckets[[subj, pred]] << item
          end

          grouped = buckets.map do |(subj, pred), group|
            values = group.map { |g| (g[:content] || g["content"]).to_s }.uniq
            group.first.merge("content" => "#{subj} — #{pred}: #{values.join(', ')}")
          end
          grouped + lexical_group_singles(singles)
        end

        def lexical_group_singles(items)
          buckets = Hash.new { |h, k| h[k] = [] }
          ungrouped = []
          items.each do |item|
            entity = lexical_entity_key(item)
            if entity
              buckets[entity] << item
            else
              ungrouped << item
            end
          end

          grouped = buckets.filter_map do |entity, group|
            next group.first if group.size == 1

            values = group.map { |g| (g[:content] || g["content"]).to_s }.uniq
            group.first.merge("content" => "#{entity}: #{values.join(' | ')}")
          end
          grouped + ungrouped
        end

        def lexical_entity_key(item)
          content = (item[:content] || item["content"]).to_s
          match = content.match(/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/)
          match&.[](1)
        end

        def item_timestamp(item)
          ed = item[:event_date] || item["event_date"]
          return Llmemory.parse_occurred_at(ed) if ed

          raw = item[:created_at] || item["created_at"]
          raw.is_a?(Time) ? raw : Llmemory.parse_occurred_at(raw)
        end

        def normalize_source_traces(source_traces, source_trace_ids)
          traces = Array(source_traces).map do |t|
            { id: (t[:id] || t["id"]).to_s, content: (t[:content] || t["content"]).to_s }
          end.reject { |t| t[:id].empty? }
          return traces if traces.any?

          Array(source_trace_ids).map { |id| { id: id.to_s, content: "" } }.reject { |t| t[:id].empty? }
        end

        def prepend_conversation_anchor(text, reference_time)
          return text unless reference_time

          anchor = Llmemory::TimeCoercion.iso8601_or_string(reference_time)
          "# Conversation anchor time (latest message): #{anchor}\n\n#{text}"
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

        def bench_truncate_extract_text(text)
          return text unless ENV["LLMEMORY_BENCH_FAST"] == "1"

          max = ENV.fetch("LLMEMORY_BENCH_EXTRACT_MAX_CHARS", "1200").to_i
          return text if max <= 0 || text.length <= max

          "[...truncated for bench extract...]\n#{text[-max, max]}"
        end

        def bench_trace?
          ENV["LLMEMORY_BENCH_TRACE"] == "1"
        end

        def bench_memorize_trace(message)
          line = "[bench-trace memorize ##{@consolidation_count}] #{message}"
          warn line
          path = ENV["LLMEMORY_BENCH_TRACE_FILE"].to_s
          File.open(path, "a") { |f| f.puts line } unless path.empty?
        rescue StandardError
          nil
        end

        def bench_trace_measure(label)
          return yield unless bench_trace?

          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
          bench_memorize_trace("#{label} #{ms.round(1)}ms")
          result
        end
      end
    end
  end
end
