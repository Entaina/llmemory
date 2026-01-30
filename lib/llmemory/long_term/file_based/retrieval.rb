# frozen_string_literal: true

require "json"

module Llmemory
  module LongTerm
    module FileBased
      class Retrieval
        def initialize(user_id:, storage:, llm: nil)
          @user_id = user_id
          @storage = storage
          @llm = llm || Llmemory::LLM.client
        end

        def retrieve(query)
          all_categories = @storage.list_categories(@user_id)
          return {} if all_categories.empty?

          relevant_categories = select_relevant_categories(query, all_categories)
          summaries = {}
          relevant_categories.each { |cat| summaries[cat] = @storage.load_category(@user_id, cat) }

          return summaries if is_sufficient?(query, summaries)

          search_query = generate_search_query(query, summaries)
          items = @storage.search_items(@user_id, search_query)
          return format_items(items) if items.any?

          resources = @storage.search_resources(@user_id, search_query)
          format_resources(resources)
        end

        private

        def select_relevant_categories(query, categories)
          return categories if categories.size <= 3
          prompt = <<~PROMPT
            Query: #{query}
            Available Categories: #{categories.join(', ')}

            Return a JSON array of the categories most relevant to this query. Example: ["work_life", "preferences"]
          PROMPT
          response = @llm.invoke(prompt.strip)
          parsed = parse_categories_response(response)
          parsed.any? ? parsed : categories.first(3)
        end

        def parse_categories_response(response)
          json = response.to_s.strip
          start_idx = json.index("[")
          return [] unless start_idx
          end_idx = json.rindex("]")
          return [] unless end_idx
          arr = JSON.parse(json[start_idx..end_idx])
          arr.is_a?(Array) ? arr.map(&:to_s) : []
        rescue JSON::ParserError
          []
        end

        def is_sufficient?(query, summaries)
          return false if summaries.values.all?(&:empty?)
          prompt = <<~PROMPT
            Query: #{query}
            Summaries: #{summaries.to_json}
            Can you answer the query comprehensively with just these summaries? Reply with exactly YES or NO.
          PROMPT
          response = @llm.invoke(prompt.strip).upcase
          response.include?("YES")
        end

        def generate_search_query(query, summaries)
          prompt = <<~PROMPT
            Query: #{query}
            Existing summary context: #{summaries.values.join("\n")[0..500]}
            Generate a short search phrase (3-6 words) to find specific facts. Return only the phrase.
          PROMPT
          @llm.invoke(prompt.strip).to_s.strip
        end

        def format_items(items)
          items.map { |i| i[:content] || i["content"] }.compact
        end

        def format_resources(resources)
          resources.map { |r| r[:text] || r["text"] }.compact
        end
      end
    end
  end
end
