# frozen_string_literal: true

require_relative "resource"
require_relative "item"
require_relative "category"
require_relative "storage"

module Llmemory
  module LongTerm
    module FileBased
      class Memory
        def initialize(user_id:, storage: nil, llm: nil, extractor: nil)
          @user_id = user_id
          @storage = storage || Storage.new
          @llm = llm || Llmemory::LLM.client
          @extractor = extractor || Llmemory::Extractors::FactExtractor.new(llm: @llm)
        end

        def memorize(conversation_text)
          resource_id = save_resource(conversation_text)
          items = @extractor.extract_items(conversation_text)
          updates_by_category = {}

          items.each do |item|
            content = item.is_a?(Hash) ? (item["content"] || item[:content]) : item.to_s
            cat = @extractor.classify_item(content)
            updates_by_category[cat] ||= []
            updates_by_category[cat] << content.to_s
            save_item(category: cat, item: item, source_resource_id: resource_id)
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
          out = []
          items.first(top_k).each do |i|
            out << {
              text: i[:content] || i["content"],
              timestamp: i[:created_at] || i["created_at"],
              score: 1.0
            }
          end
          resources.first([top_k - out.size, 0].max).each do |r|
            out << {
              text: r[:text] || r["text"],
              timestamp: r[:created_at] || r["created_at"],
              score: 0.9
            }
          end
          out
        end

        attr_reader :storage, :user_id

        private

        def save_resource(text)
          @storage.save_resource(@user_id, text)
        end

        def save_item(category:, item:, source_resource_id:)
          content = item.is_a?(Hash) ? item["content"] || item[:content] : item.to_s
          @storage.save_item(@user_id, category: category, content: content, source_resource_id: source_resource_id)
        end
      end
    end
  end
end
