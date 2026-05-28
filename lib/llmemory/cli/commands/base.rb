# frozen_string_literal: true

module Llmemory
  module Cli
    module Commands
      class Base
        def run(argv)
          opts = parse_options(argv)
          execute(argv, opts)
        end

        def parse_options(argv)
          OptionParser.new do |opts|
            option_parser(opts)
          end.parse!(argv)
        end

        def option_parser(parser)
          # Override in subclasses to add options
        end

        def execute(_argv, _opts)
          raise NotImplementedError, "#{self.class}#execute must be implemented"
        end

        protected

        def short_term_store(store_type = nil)
          type = (store_type || Llmemory.configuration.short_term_store).to_s.to_sym
          case type
          when :memory then Llmemory::ShortTerm::Stores::MemoryStore.new
          when :redis then Llmemory::ShortTerm::Stores::RedisStore.new
          when :postgres then Llmemory::ShortTerm::Stores::PostgresStore.new
          when :active_record, :activerecord
            require_relative "../../short_term/stores/active_record_store"
            Llmemory::ShortTerm::Stores::ActiveRecordStore.new
          else
            Llmemory::ShortTerm::Stores::MemoryStore.new
          end
        end

        def file_based_storage(store_type = nil)
          type = (store_type || Llmemory.configuration.long_term_store).to_s.to_sym
          case type
          when :memory then Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
          when :file
            Llmemory::LongTerm::FileBased::Storages::FileStorage.new(
              base_path: Llmemory.configuration.long_term_storage_path
            )
          when :postgres, :database
            Llmemory::LongTerm::FileBased::Storages::DatabaseStorage.new(
              database_url: Llmemory.configuration.database_url
            )
          when :active_record, :activerecord
            require_relative "../../long_term/file_based/storages/active_record_storage"
            Llmemory::LongTerm::FileBased::Storages::ActiveRecordStorage.new
          else
            Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
          end
        end

        def graph_based_storage(store_type = nil)
          type = (store_type || :memory).to_s.to_sym
          case type
          when :memory then Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new
          when :active_record, :activerecord
            require_relative "../../long_term/graph_based/storages/active_record_storage"
            Llmemory::LongTerm::GraphBased::Storages::ActiveRecordStorage.new
          else
            Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new
          end
        end

        def episodic_storage(store_type = nil)
          Llmemory::LongTerm::Episodic::Storages.build(store: (store_type || Llmemory.configuration.long_term_store))
        end

        def procedural_storage(store_type = nil)
          Llmemory::LongTerm::Procedural::Storages.build(store: (store_type || Llmemory.configuration.long_term_store))
        end
      end
    end
  end
end
