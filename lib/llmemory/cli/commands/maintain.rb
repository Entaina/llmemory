# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      # Runs the cognitive maintenance pass for a user: reflect -> mine skills ->
      # expire. Each step is isolated; failures are reported, not fatal.
      class Maintain < Commands::Base
        def option_parser(parser)
          parser.on("--[no-]reflect", "Distill insights from recent episodes (default: on)") { |v| @reflect = v }
          parser.on("--mine-skills", "Mine and register skills from episodes (default: config)") { @mine = true }
          parser.on("--[no-]expire", "Soft-archive entries past their TTL (default: on)") { |v| @expire = v }
          parser.on("--window N", Integer, "Episodes to reflect over (default 10)") { |v| @window = v }
          parser.on("--store TYPE", "Storage type (memory|file|postgres|active_record)") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory maintain USER_ID [--[no-]reflect] [--mine-skills] [--[no-]expire] [--window N] [--store TYPE]"
            exit 1
          end

          opts = {
            episodic: Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id, storage: episodic_storage(@store_type)),
            procedural: Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id, storage: procedural_storage(@store_type)),
            semantic: build_semantic(user_id),
            reflect: @reflect.nil? ? true : @reflect,
            expire: @expire.nil? ? true : @expire
          }
          opts[:mine_skills] = @mine unless @mine.nil?
          opts[:reflection_window] = @window if @window

          report = Llmemory::Maintenance::CognitivePass.run!(user_id, **opts)
          print_report(user_id, report)
        end

        private

        def build_semantic(user_id)
          if Llmemory.configuration.long_term_type.to_s == "graph_based"
            Llmemory::LongTerm::GraphBased::Memory.new(user_id: user_id, storage: graph_based_storage(@store_type))
          else
            Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: file_based_storage(@store_type))
          end
        end

        def print_report(user_id, report)
          expired = report[:expired] || {}
          puts "Cognitive pass for #{user_id}:"
          puts "  insights:     #{Array(report[:insights]).size}"
          puts "  skills mined: #{Array(report[:mined]).size}"
          puts "  expired:      episodic=#{expired[:episodic] || 0} procedural=#{expired[:procedural] || 0}"
          errors = report[:errors] || {}
          errors.each { |step, msg| puts "  error (#{step}): #{msg}" }
        end
      end
    end
  end
end
