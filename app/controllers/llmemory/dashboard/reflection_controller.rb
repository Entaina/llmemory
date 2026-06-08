# frozen_string_literal: true

module Llmemory
  module Dashboard
    # Read-only landing for reflection. Triggers (POST #run) build a Reflector
    # over the configured episodic + semantic memories and run a single pass
    # over the last N episodes.
    class ReflectionController < ApplicationController
      def show
        @user_id = params[:user_id]
        @recent_window = (params[:window].presence || 10).to_i
        @recent_episodes = episodic_storage.list_episodes(@user_id, limit: @recent_window)
      end

      def run
        user_id = params[:user_id]
        window = (params[:window].presence || 10).to_i
        episodic = Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id, storage: episodic_storage)
        semantic = build_semantic_memory(user_id)
        insight_ids = Llmemory::Reflection::Reflector.new(episodic: episodic, semantic: semantic).reflect(window: window)
        redirect_to user_reflection_path(user_id), notice: "Reflection produced #{insight_ids.size} insight(s)."
      rescue Llmemory::LLMError => e
        redirect_to user_reflection_path(user_id), alert: "Reflection failed: #{e.message}"
      end

      private

      def build_semantic_memory(user_id)
        if graph_based?
          Llmemory::LongTerm::GraphBased::Memory.new(user_id: user_id, storage: graph_based_storage)
        else
          Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: file_based_storage)
        end
      end
    end
  end
end
