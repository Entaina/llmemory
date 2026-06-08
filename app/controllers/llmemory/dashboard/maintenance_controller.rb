module Llmemory
  module Dashboard
    # Cognitive maintenance surface (SF20): trigger a maintenance pass and review
    # mined-skill proposals before registering them (human-in-the-loop).
    class MaintenanceController < ApplicationController
      def show
        @user_id = params[:user_id]
        @window = (params[:window].presence || 10).to_i
        @recent_episodes = episodic_storage.list_episodes(@user_id, limit: @window)
        @proposals = session_proposals
      end

      # Runs the full cognitive pass (reflect -> mine -> expire) and reports.
      def run
        user_id = params[:user_id]
        window = (params[:window].presence || 10).to_i
        report = Llmemory::Maintenance::CognitivePass.run!(
          user_id,
          episodic: episodic_memory(user_id),
          procedural: procedural_memory(user_id),
          semantic: build_semantic_memory(user_id),
          mine_skills: params[:mine_skills].present?,
          reflection_window: window
        )
        redirect_to user_maintenance_path(user_id), notice: pass_notice(report)
      rescue Llmemory::LLMError => e
        redirect_to user_maintenance_path(user_id), alert: "Maintenance pass failed: #{e.message}"
      end

      # Mines skills WITHOUT registering — returns proposals for review.
      def mine
        user_id = params[:user_id]
        window = (params[:window].presence || 20).to_i
        proposals = Llmemory::SkillMining::Miner.new(
          episodic: episodic_memory(user_id), procedural: procedural_memory(user_id)
        ).mine(window: window, auto_register: false)
        store_proposals(proposals)
        redirect_to user_maintenance_path(user_id), notice: "Mined #{proposals.size} skill proposal(s) for review."
      rescue Llmemory::LLMError => e
        redirect_to user_maintenance_path(user_id), alert: "Skill mining failed: #{e.message}"
      end

      # Registers a single reviewed proposal into procedural memory.
      def register
        user_id = params[:user_id]
        procedural_memory(user_id).register_skill(
          name: params[:name], body: params[:body], description: params[:description].presence,
          kind: params[:kind].presence || Llmemory::LongTerm::Procedural::Skill::DEFAULT_KIND,
          provenance: Llmemory::Provenance.build(method: "skill_mining")
        )
        redirect_to user_maintenance_path(user_id), notice: "Registered skill #{params[:name]}."
      end

      private

      def episodic_memory(user_id)
        Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id, storage: episodic_storage)
      end

      def procedural_memory(user_id)
        Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id, storage: procedural_storage)
      end

      def build_semantic_memory(user_id)
        if graph_based?
          Llmemory::LongTerm::GraphBased::Memory.new(user_id: user_id, storage: graph_based_storage)
        else
          Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: file_based_storage)
        end
      end

      def pass_notice(report)
        expired = report[:expired] || {}
        msg = "Pass complete: #{Array(report[:insights]).size} insight(s), " \
              "#{Array(report[:mined]).size} skill(s) mined, " \
              "expired episodic=#{expired[:episodic] || 0} procedural=#{expired[:procedural] || 0}."
        errors = report[:errors] || {}
        errors.empty? ? msg : "#{msg} Errors: #{errors.map { |k, v| "#{k}: #{v}" }.join('; ')}"
      end

      # Proposals are stashed in the session so they survive the redirect to
      # `show` without being persisted to a store before the user confirms.
      def store_proposals(proposals)
        session[:llmemory_skill_proposals] = proposals
      end

      def session_proposals
        Array(session.delete(:llmemory_skill_proposals)).map { |p| p.respond_to?(:symbolize_keys) ? p.symbolize_keys : p }
      end
    end
  end
end
