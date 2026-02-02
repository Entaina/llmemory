# frozen_string_literal: true

module Llmemory
  module Dashboard
    class StatsController < ApplicationController
      def index
        @user_id = params[:user_id]
        @sessions = short_term_store.list_sessions(user_id: @user_id)

        if graph_based?
          @nodes_count = graph_based_storage.count_nodes(@user_id)
          @edges_count = graph_based_storage.count_edges(@user_id)
        else
          @items_count = file_based_storage.count_items(user_id: @user_id)
          @categories_count = file_based_storage.list_categories(@user_id).size
          @resources_count = file_based_storage.list_resources(user_id: @user_id).size
        end
      end
    end
  end
end
