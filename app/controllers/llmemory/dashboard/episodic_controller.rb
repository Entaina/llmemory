# frozen_string_literal: true

module Llmemory
  module Dashboard
    class EpisodicController < ApplicationController
      def index
        @user_id = params[:user_id]
        @limit = (params[:limit].presence || 50).to_i
        @offset = (params[:offset].presence || 0).to_i
        @episodes = episodic_storage.list_episodes(@user_id, limit: @limit, offset: @offset)
        @total = episodic_storage.count_episodes(@user_id)
      end

      def forget
        memory = Llmemory::LongTerm::Episodic::Memory.new(user_id: params[:user_id], storage: episodic_storage)
        mode = params[:mode].to_s == "hard" ? :hard : :soft
        memory.forget(ids: [params[:id]], reason: params[:reason], mode: mode)
        redirect_to user_episodic_path(params[:user_id]), notice: "Forgot episode #{params[:id]} (#{mode})."
      end
    end
  end
end
