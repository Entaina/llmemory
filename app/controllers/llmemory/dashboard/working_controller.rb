# frozen_string_literal: true

module Llmemory
  module Dashboard
    class WorkingController < ApplicationController
      def show
        @user_id = params[:user_id]
        @session_id = params[:session_id]
        @working = Llmemory::WorkingMemory.new(user_id: @user_id, session_id: @session_id, store: short_term_store)
        @slots = @working.to_h
      end
    end
  end
end
