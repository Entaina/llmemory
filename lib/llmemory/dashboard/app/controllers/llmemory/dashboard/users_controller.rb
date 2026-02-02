# frozen_string_literal: true

module Llmemory
  module Dashboard
    class UsersController < ApplicationController
      def index
        @users = short_term_store.list_users
        @users = (@users + long_term_user_ids).uniq
      end

      def show
        @user_id = params[:user_id]
        @sessions = short_term_store.list_sessions(user_id: @user_id)
      end

      protected

      def long_term_user_ids
        if graph_based?
          graph_based_storage.list_users
        else
          file_based_storage.list_users
        end
      end
    end
  end
end
