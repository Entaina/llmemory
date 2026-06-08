# frozen_string_literal: true

module Llmemory
  module Dashboard
    class ProceduralController < ApplicationController
      def index
        @user_id = params[:user_id]
        @limit = (params[:limit].presence || 50).to_i
        @offset = (params[:offset].presence || 0).to_i
        @skills = procedural_storage.list_skills(@user_id, limit: @limit, offset: @offset)
        @total = procedural_storage.count_skills(@user_id)
      end

      def forget
        memory = Llmemory::LongTerm::Procedural::Memory.new(user_id: params[:user_id], storage: procedural_storage)
        mode = params[:mode].to_s == "hard" ? :hard : :soft
        memory.forget(ids: [params[:id]], reason: params[:reason], mode: mode)
        redirect_to user_procedural_path(params[:user_id]), notice: "Forgot skill #{params[:id]} (#{mode})."
      end
    end
  end
end
