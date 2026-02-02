# frozen_string_literal: true

module Llmemory
  module Dashboard
    class LongTermController < ApplicationController
      before_action :ensure_file_based

      def index
        @user_id = params[:user_id]
        @items = file_based_storage.list_items(user_id: @user_id, limit: 100)
        @resources = file_based_storage.list_resources(user_id: @user_id, limit: 50)
      end

      def categories
        @user_id = params[:user_id]
        @category_names = file_based_storage.list_categories(@user_id)
        @categories_content = {}
        @category_names.each do |name|
          @categories_content[name] = file_based_storage.load_category(@user_id, name)
        end
      end

      private

      def ensure_file_based
        return if file_based?
        redirect_to root_path, alert: "Long-term file-based view only available when long_term_type is file_based."
      end
    end
  end
end
