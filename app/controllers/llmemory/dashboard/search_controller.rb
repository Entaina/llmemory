# frozen_string_literal: true

module Llmemory
  module Dashboard
    class SearchController < ApplicationController
      def index
        @query = params[:q].to_s.strip
        @user_id = params[:user_id].presence

        if @query.empty?
          @short_term_results = []
          @file_based_results = []
          @graph_results = []
          return
        end

        if @user_id.present?
          @short_term_results = search_short_term(@user_id)
          if file_based?
            @file_based_results = file_based_storage.search_items(@user_id, @query) +
              file_based_storage.search_resources(@user_id, @query).map { |r| r.merge(type: "resource") }
          else
            @file_based_results = []
          end
          if graph_based?
            nodes = graph_based_storage.list_nodes(@user_id)
            q = @query.downcase
            @graph_results = nodes.select { |n| (n.respond_to?(:name) ? n.name : n[:name]).to_s.downcase.include?(q) }
          else
            @graph_results = []
          end
        else
          @short_term_results = []
          @file_based_results = []
          @graph_results = []
        end
      end

      private

      def search_short_term(user_id)
        sessions = short_term_store.list_sessions(user_id: user_id)
        results = []
        sessions.each do |session_id|
          state = short_term_store.load(user_id, session_id)
          next unless state
          messages = state[:messages] || state["messages"] || []
          messages.each do |m|
            content = (m[:content] || m["content"]).to_s
            next unless content.downcase.include?(@query.downcase)
            results << { session_id: session_id, role: m[:role] || m["role"], content: content }
          end
        end
        results
      end
    end
  end
end
