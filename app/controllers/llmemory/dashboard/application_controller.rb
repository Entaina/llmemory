# frozen_string_literal: true

module Llmemory
  module Dashboard
    class ApplicationController < ActionController::Base
      before_action :ensure_dashboard_authorized!

      helper_method :short_term_store, :file_based_storage, :graph_based_storage,
                    :episodic_storage, :procedural_storage, :forget_log,
                    :file_based?, :graph_based?

      protected

      def ensure_dashboard_authorized!
        return unless Llmemory.configuration.dashboard_require_auth?
        auth = Llmemory.configuration.dashboard_auth
        return if auth.respond_to?(:call) && auth.call(self)

        head :forbidden
      end

      protected

      def short_term_store
        @short_term_store ||= build_short_term_store
      end

      def file_based_storage
        @file_based_storage ||= build_file_based_storage
      end

      def graph_based_storage
        @graph_based_storage ||= build_graph_based_storage
      end

      def episodic_storage
        @episodic_storage ||= Llmemory::LongTerm::Episodic::Storages.build
      end

      def procedural_storage
        @procedural_storage ||= Llmemory::LongTerm::Procedural::Storages.build
      end

      def forget_log
        @forget_log ||= Llmemory::ForgetLog.new
      end

      def long_term_type
        Llmemory.configuration.long_term_type.to_s
      end

      def graph_based?
        long_term_type == "graph_based"
      end

      def file_based?
        long_term_type == "file_based"
      end

      private

      def build_short_term_store
        type = (Llmemory.configuration.short_term_store).to_s.to_sym
        case type
        when :memory then Llmemory::ShortTerm::Stores::MemoryStore.new
        when :redis then Llmemory::ShortTerm::Stores::RedisStore.new
        when :postgres then Llmemory::ShortTerm::Stores::PostgresStore.new
        when :active_record, :activerecord
          require "llmemory/short_term/stores/active_record_store"
          Llmemory::ShortTerm::Stores::ActiveRecordStore.new
        else
          Llmemory::ShortTerm::Stores::MemoryStore.new
        end
      end

      def build_file_based_storage
        type = (Llmemory.configuration.long_term_store).to_s.to_sym
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
          require "llmemory/long_term/file_based/storages/active_record_storage"
          Llmemory::LongTerm::FileBased::Storages::ActiveRecordStorage.new
        else
          Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
        end
      end

      def build_graph_based_storage
        type = (Llmemory.configuration.long_term_store).to_s.to_sym
        case type
        when :memory then Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new
        when :active_record, :activerecord
          require "llmemory/long_term/graph_based/storages/active_record_storage"
          Llmemory::LongTerm::GraphBased::Storages::ActiveRecordStorage.new
        else
          Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new
        end
      end
    end
  end
end
