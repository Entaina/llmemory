# frozen_string_literal: true

module Llmemory
  module Dashboard
    class ForgetLogController < ApplicationController
      def show
        @user_id = params[:user_id]
        @entries = forget_log.entries(@user_id)
      end
    end
  end
end
