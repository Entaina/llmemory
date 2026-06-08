# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      # Mines reusable skills from a user's successful episodes. Human-in-the-loop
      # by default: prints proposals and writes nothing unless --register is given.
      class MineSkills < Commands::Base
        def option_parser(parser)
          parser.on("--window N", Integer, "Episodes to mine (default 20)") { |v| @window = v }
          parser.on("--outcomes LIST", "Comma-separated outcome allowlist (e.g. success,recovered)") { |v| @outcomes = v.split(",").map(&:strip) }
          parser.on("--register", "Register the proposals instead of only printing them") { @register = true }
          parser.on("--store TYPE", "Storage type (memory|file|postgres|active_record)") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory mine-skills USER_ID [--window N] [--outcomes LIST] [--register] [--store TYPE]"
            exit 1
          end

          episodic = Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id, storage: episodic_storage(@store_type))
          procedural = Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id, storage: procedural_storage(@store_type))
          result = Llmemory::SkillMining::Miner.new(episodic: episodic, procedural: procedural).mine(
            window: @window || Llmemory::SkillMining::Miner::DEFAULT_WINDOW,
            outcomes: @outcomes,
            auto_register: @register
          )

          if result.empty?
            puts "No skills could be mined for user #{user_id}."
            return
          end

          if @register
            puts "Registered #{result.size} mined skill(s): #{result.join(', ')}"
          else
            puts "#{result.size} skill proposal(s) for user #{user_id} (not registered):"
            result.each do |p|
              puts "  - #{p[:name]} (#{p[:kind]}, confidence: #{p[:confidence]}): #{p[:description] || p[:body]}"
            end
          end
        end
      end
    end
  end
end
