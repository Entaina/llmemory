# frozen_string_literal: true

module Llmemory
  module Maintenance
    # The cognitive maintenance pass closes CoALA's learning loop in one
    # scheduled step. Independently, the gem exposes consolidation (short-term ->
    # semantic), reflection (episodic -> insights), skill mining (episodic ->
    # procedural) and TTL expiry. This pass orchestrates them so an agent learns
    # from its experience and keeps its memory healthy without the consumer
    # wiring each step by hand.
    #
    # Designed to run as a maintenance task (cron / Rails Job), per user. Each
    # step is isolated: a failure in one is captured in the returned report
    # (`:errors`) and never aborts the others.
    #
    # Returns:
    #   {
    #     consolidated: true/false/nil,   # nil when no `memory:` was supplied
    #     insights: [insight_id, ...],
    #     mined: [proposal_or_skill_id, ...],
    #     expired: { episodic: N, procedural: M },
    #     errors: { reflect: "...", mine: "...", ... }   # only failed steps
    #   }
    class CognitivePass
      def self.run!(user_id, **kwargs)
        new(user_id, **kwargs).run!
      end

      def initialize(user_id, memory: nil, episodic: nil, procedural: nil, semantic: nil,
                     llm: nil, reflect: true, mine_skills: nil, expire: true,
                     reflection_window: 10, mining_window: Llmemory::SkillMining::Miner::DEFAULT_WINDOW)
        @user_id = user_id
        @memory = memory
        @episodic = episodic
        @procedural = procedural
        @semantic = semantic
        @llm = llm
        @reflect = reflect
        @mine_skills = mine_skills.nil? ? Llmemory.configuration.skill_mining_enabled : mine_skills
        @expire = expire
        @reflection_window = reflection_window
        @mining_window = mining_window
      end

      def run!
        report = { consolidated: nil, insights: [], mined: [], expired: { episodic: 0, procedural: 0 }, errors: {} }

        step(report, :consolidate) { report[:consolidated] = consolidate } if @memory
        step(report, :reflect)     { report[:insights] = reflect } if @reflect
        step(report, :mine)        { report[:mined] = mine } if @mine_skills
        step(report, :expire)      { report[:expired] = expire } if @expire

        report
      end

      private

      def step(report, name)
        yield
      rescue StandardError => e
        report[:errors][name] = e.message
      end

      def consolidate
        @memory.consolidate!
      end

      def reflect
        Reflection::Reflector.new(episodic: episodic, semantic: semantic, llm: @llm)
          .reflect(window: @reflection_window)
      end

      def mine
        SkillMining::Miner.new(episodic: episodic, procedural: procedural, llm: @llm)
          .mine(window: @mining_window, auto_register: true)
      end

      def expire
        TTLExpiry.run!(@user_id, episodic: episodic, procedural: procedural)
      end

      def episodic
        @episodic ||= @memory&.episodic || Llmemory::LongTerm::Episodic::Memory.new(user_id: @user_id)
      end

      def procedural
        @procedural ||= @memory&.procedural || Llmemory::LongTerm::Procedural::Memory.new(user_id: @user_id)
      end

      def semantic
        @semantic ||= build_semantic
      end

      def build_semantic
        llm_opts = @llm ? { llm: @llm } : {}
        case (Llmemory.configuration.long_term_type || :file_based).to_s.to_sym
        when :graph_based
          Llmemory::LongTerm::GraphBased::Memory.new(
            user_id: @user_id, storage: Llmemory::LongTerm::GraphBased::Storages.build, **llm_opts
          )
        else
          Llmemory::LongTerm::FileBased::Memory.new(
            user_id: @user_id, storage: Llmemory::LongTerm::FileBased::Storages.build, **llm_opts
          )
        end
      end
    end
  end
end
