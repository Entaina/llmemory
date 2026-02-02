# frozen_string_literal: true

module Llmemory
  module Dashboard
    class GraphController < ApplicationController
      def index
        @user_id = params[:user_id]
        @nodes = graph_based_storage.list_nodes(@user_id, limit: 200)
        @edges = graph_based_storage.list_edges(@user_id, limit: 300)
      end

      def show
        index
        render :index
      end
    end
  end
end
