# frozen_string_literal: true

module Llmemory
  module Dashboard
    class ShortTermController < ApplicationController
      def show
        @user_id = params[:user_id]
        @session_id = params[:session_id].presence || "default"
        state = short_term_store.load(@user_id, @session_id)
        @messages = state ? (state[:messages] || state["messages"] || []) : []
        @sessions = short_term_store.list_sessions(user_id: @user_id)
      end
    end
  end
end
