# frozen_string_literal: true

require "json"

module Llmemory
  module Extractors
    class FactExtractor
      PARSE_FAILURE_KEY = :llmemory_extract_parse_failures

      class << self
        def consume_parse_failures
          count = Thread.current[PARSE_FAILURE_KEY].to_i
          Thread.current[PARSE_FAILURE_KEY] = 0
          count
        end

        def record_parse_failure
          Thread.current[PARSE_FAILURE_KEY] = Thread.current[PARSE_FAILURE_KEY].to_i + 1
        end
      end

      def initialize(llm: nil)
        @llm = llm || Llmemory::LLM.client
      end

      EXTRACT_ITEMS_JSON_SCHEMA = {
        name: "fact_extraction",
        schema: {
          type: "object",
          properties: {
            items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  content: { type: "string" },
                  importance: { type: "number" },
                  event_date: { type: ["string", "null"] },
                  subject: { type: ["string", "null"] },
                  predicate: { type: ["string", "null"] },
                  category: { type: "string" }
                },
                required: %w[content importance category],
                additionalProperties: false
              }
            }
          },
          required: ["items"],
          additionalProperties: false
        }
      }.freeze

      def extract_items(conversation_text, reference_time: nil, known_facts: nil)
        chunks = chunk_conversation(conversation_text.to_s)
        merged = chunks.flat_map do |chunk|
          extract_items_from_text(chunk, reference_time: reference_time, known_facts: known_facts)
        end
        dedupe_extracted_items(merged)
      end

      def extract_items_from_text(conversation_text, reference_time: nil, known_facts: nil)
        prompt = build_extract_prompt(conversation_text, reference_time: reference_time, known_facts: known_facts)
        if bench_fast_extract?
          bench_extract_trace("invoke start prompt_chars=#{prompt.length}")
          response = @llm.invoke(prompt.strip)
          bench_extract_trace("invoke done response_chars=#{response.to_s.length}")
          items = parse_items_response(response, reference_time: reference_time)
          return retry_structured_if_empty(items, prompt, conversation_text, reference_time: reference_time)
        end

        items = extract_items_structured(prompt.strip, reference_time: reference_time)
        return items if items.any?

        response = @llm.invoke(prompt.strip)
        items = parse_items_response(response, reference_time: reference_time)
        retry_structured_if_empty(items, prompt, conversation_text, reference_time: reference_time)
      end

      def build_extract_prompt(conversation_text, reference_time: nil, known_facts: nil)
        anchor = reference_time ? Llmemory::TimeCoercion.iso8601_or_string(reference_time) : nil
        anchor_line = anchor ? "Conversation anchor time (latest message): #{anchor}\n" : ""
        known_line = format_known_facts(known_facts)
        <<~PROMPT
          Extract discrete facts from this conversation.
          Focus on preferences, behaviors, and important details.
          #{anchor_line}#{known_line}When the conversation uses relative dates (yesterday, last week, this month), resolve them to an absolute calendar date using the anchor time when possible.
          Resolve coreferences using known facts (e.g. "her home country" → country name from prior facts). Reuse the same subject/predicate strings when the fact extends an existing one.
          When the speaker lists multiple values (places, activities, likes), emit one JSON object per value with the same subject and predicate.
          Emit explicit identity or role facts when stated or clearly implied (e.g. transgender woman, adoption researcher).
          When someone says they will "do research" or "look into" a topic, record subject+predicate research_target with the topic (e.g. adoption agencies), distinct from generic career exploration.
          For deadlines and commitments, emit subject, predicate (deadline/due_date), event_date (YYYY-MM-DD), and content with the ISO date.
          Conversation: #{conversation_text}
          Return as JSON array of objects with "content", "importance" (0-1), optional "event_date" (ISO8601 date YYYY-MM-DD or null), optional "subject"/"predicate", and "category" (lowercase_with_underscores).
          Put resolved absolute dates in content when the fact is time-specific (e.g. "Caroline went to LGBTQ support group on 2023-05-07").
          For counting questions, emit a fact with the numeric count when the conversation states it (e.g. "User visited the library 10 times").
          Importance: 0.8-0.95 for preferences/corrections/decisions, 0.5-0.8 for factual context, 0.3-0.5 for ephemeral.
          Example: [{"content": "User prefers Ruby", "importance": 0.9, "event_date": null, "category": "preferences"}]
        PROMPT
      end

      def retry_structured_if_empty(items, prompt, conversation_text, reference_time:)
        return items if items.any?
        return items if conversation_text.to_s.length < 80
        return items if bench_fast_extract?
        return items unless @llm.respond_to?(:invoke_with_json_schema)

        structured = extract_items_structured(prompt.strip, reference_time: reference_time)
        structured.any? ? structured : items
      end

      def chunk_conversation(text)
        max_chars = extraction_chunk_chars
        return [text] if text.length <= max_chars

        chunks = []
        buffer = +""
        text.each_line do |line|
          if buffer.length + line.length > max_chars && buffer.length.positive?
            chunks << buffer
            buffer = +""
          end
          buffer << line
        end
        chunks << buffer if buffer.length.positive?
        chunks.empty? ? [text] : chunks
      end

      def extraction_chunk_chars
        explicit = ENV["LLMEMORY_EXTRACTION_CHUNK_CHARS"].to_i
        return explicit if explicit.positive?

        bench = ENV["LLMEMORY_BENCH_EXTRACT_MAX_CHARS"].to_i
        return bench if bench.positive?

        4_000
      end

      def dedupe_extracted_items(items)
        seen = {}
        items.filter_map do |item|
          content = (item["content"] || item[:content]).to_s.strip
          next if content.empty?
          next if seen[content]

          seen[content] = true
          item
        end
      end

      def extract_items_structured(prompt, reference_time: nil)
        return [] if bench_fast_extract?
        return [] unless @llm.respond_to?(:invoke_with_json_schema)

        parsed = @llm.invoke_with_json_schema(prompt, EXTRACT_ITEMS_JSON_SCHEMA)
        rows = Array(parsed["items"] || parsed[:items])
        return [] if rows.empty?

        resolver = Llmemory::Temporal::RelativeDateResolver.new
        rows.map { |item| normalize_extracted_item(item, resolver: resolver, reference_time: reference_time) }
      rescue Llmemory::LLMError
        []
      end

      def bench_fast_extract?
        ENV["LLMEMORY_BENCH_FAST"] == "1"
      end

      def bench_extract_trace(message)
        return unless ENV["LLMEMORY_BENCH_TRACE"] == "1"

        line = "[bench-trace extract] #{message}"
        warn line
        path = ENV["LLMEMORY_BENCH_TRACE_FILE"].to_s
        File.open(path, "a") { |f| f.puts line } unless path.empty?
      rescue StandardError
        nil
      end

      def format_known_facts(known_facts)
        list = Array(known_facts).map(&:to_s).reject(&:empty?)
        return "" if list.empty?

        bullets = list.map { |f| "- #{f}" }.join("\n")
        "Known facts about entities in this conversation:\n#{bullets}\n\n"
      end

      def evolve_summary(existing:, new_memories:)
        memory_list_text = Array(new_memories).map { |m| "- #{m}" }.join("\n")
        prompt = <<~PROMPT
          You are a Memory Synchronization Specialist.
          Topic Scope: User Profile

          ## Original Profile
          #{existing.to_s.empty? ? "No existing profile." : existing}

          ## New Memory Items to Integrate
          #{memory_list_text}

          # Task
          1. Update: If new items conflict with the Original Profile, overwrite the old facts.
          2. Add: If items are new, append them logically.
          3. Output: Return ONLY the updated markdown profile.
        PROMPT
        @llm.invoke(prompt.strip).to_s
      end

      def classify_item(content)
        classify_items([content])[content.to_s] || "general"
      end

      CLASSIFY_JSON_SCHEMA = {
        name: "fact_classification",
        schema: {
          type: "object",
          properties: {
            items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  content: { type: "string" },
                  category: { type: "string" }
                },
                required: ["content", "category"],
                additionalProperties: false
              }
            }
          },
          required: ["items"],
          additionalProperties: false
        }
      }.freeze

      def classify_items(contents)
        list = Array(contents).map(&:to_s).reject(&:empty?)
        return {} if list.empty?

        if @llm.respond_to?(:invoke_with_json_schema)
          begin
            numbered = list.map.with_index { |c, i| "#{i + 1}. #{c}" }.join("\n")
            prompt = <<~PROMPT
              Classify each fact into ONE category. Use lowercase with underscores.
              Examples: work_life, personal_life, preferences, general.

              Facts:
              #{numbered}

              Return one category per fact in the same order.
            PROMPT
            parsed = @llm.invoke_with_json_schema(prompt.strip, CLASSIFY_JSON_SCHEMA)
            mapped = map_classifications(parsed, list)
            return mapped if mapped.size == list.size
          rescue Llmemory::LLMError
            # fall back to per-item classification
          end
        end

        list.each_with_object({}) { |content, acc| acc[content] = classify_item_fallback(content) }
      end

      private

      def classify_item_fallback(content)
        return "general" if content.to_s.strip.empty?
        prompt = <<~PROMPT
          Classify this fact into ONE category. Use lowercase with underscores. Examples: work_life, personal_life, preferences, general.
          Fact: #{content}
          Return ONLY the category name, nothing else.
        PROMPT
        result = @llm.invoke(prompt.strip).to_s.strip.downcase.gsub(/\s+/, "_")
        result.empty? ? "general" : result
      end

      def map_classifications(parsed, contents)
        items = Array(parsed["items"] || parsed[:items])
        by_content = items.each_with_object({}) do |row, acc|
          content = (row["content"] || row[:content]).to_s
          category = (row["category"] || row[:category]).to_s.strip.downcase.gsub(/\s+/, "_")
          acc[content] = category.empty? ? "general" : category
        end
        contents.each_with_object({}) do |content, acc|
          acc[content] = by_content[content] || classify_item_fallback(content)
        end
      end

      def parse_items_response(response, reference_time: nil)
        json = extract_json_array(response)
        return [] unless json

        resolver = Llmemory::Temporal::RelativeDateResolver.new
        json.filter_map do |item|
          normalize_extracted_item(item, resolver: resolver, reference_time: reference_time)
        rescue StandardError
          self.class.record_parse_failure
          nil
        end
      end

      def normalize_extracted_item(item, resolver:, reference_time:)
        h = if item.is_a?(Hash)
              item.transform_keys(&:to_s)
            else
              { "content" => item.to_s }
            end
        imp = h["importance"] || h[:importance]
        h["importance"] = imp.nil? ? 0.7 : (imp.to_f.between?(0, 1) ? imp.to_f : 0.7)
        content = (h["content"] || h[:content]).to_s
        event_date = h["event_date"] || h[:event_date]
        if reference_time && (event_date.nil? || event_date.to_s.strip.empty?)
          resolved = resolver.resolve(content, reference_time: reference_time)
          h["content"] = resolved[:content]
          h["event_date"] = resolved[:event_date] if resolved[:event_date]
        end
        h
      end

      def extract_json_array(response)
        response = response.to_s.strip
        start_idx = response.index("[")
        return nil unless start_idx
        end_idx = response.rindex("]")
        fragment = end_idx ? response[start_idx..end_idx] : response[start_idx..]
        JSON.parse(fragment)
      rescue JSON::ParserError
        salvaged = salvage_json_objects(response[start_idx..] || response)
        self.class.record_parse_failure if salvaged.nil? || salvaged.empty?
        salvaged
      end

      def salvage_json_objects(fragment)
        objects = []
        i = 0
        while (start = fragment.index("{", i))
          depth = 0
          parsed = nil
          (start...fragment.length).each do |j|
            depth += 1 if fragment[j] == "{"
            depth -= 1 if fragment[j] == "}"
            next unless depth.zero?

            begin
              parsed = JSON.parse(fragment[start..j])
            rescue JSON::ParserError
              parsed = nil
            end
            i = j + 1
            break
          end
          objects << parsed if parsed.is_a?(Hash)
          i = start + 1 if depth != 0
        end
        objects.empty? ? nil : objects
      end
    end
  end
end
