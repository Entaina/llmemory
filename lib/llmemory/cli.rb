# frozen_string_literal: true

require "optparse"
require_relative "cli/commands/base"
require_relative "cli/commands/users"
require_relative "cli/commands/short_term"
require_relative "cli/commands/long_term"
require_relative "cli/commands/episodic"
require_relative "cli/commands/procedural"
require_relative "cli/commands/working"
require_relative "cli/commands/forget_log"
require_relative "cli/commands/mine_skills"
require_relative "cli/commands/maintain"
require_relative "cli/commands/stats"
require_relative "cli/commands/search"
require_relative "cli/commands/mcp"

module Llmemory
  class CLI
    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      return print_help if argv.empty?
      first = argv.first
      if first == "--help" || first == "-h"
        print_help
        return
      end
      subcommand = argv.shift
      command_class = find_command(subcommand)
      if command_class
        command_class.new.run(argv)
      else
        $stderr.puts "llmemory: unknown command '#{subcommand}'"
        $stderr.puts "Run 'llmemory --help' for usage."
        exit 1
      end
    end

    private

    def find_command(name)
      normalized = name.tr("-", "_").downcase
      {
        "users" => Cli::Commands::Users,
        "short_term" => Cli::Commands::ShortTerm,
        "facts" => Cli::Commands::LongTerm::Facts,
        "categories" => Cli::Commands::LongTerm::Categories,
        "resources" => Cli::Commands::LongTerm::Resources,
        "nodes" => Cli::Commands::LongTerm::Nodes,
        "edges" => Cli::Commands::LongTerm::Edges,
        "graph" => Cli::Commands::LongTerm::Graph,
        "episodes" => Cli::Commands::Episodic,
        "skills" => Cli::Commands::Procedural,
        "working" => Cli::Commands::Working,
        "forget_log" => Cli::Commands::ForgetLog,
        "mine_skills" => Cli::Commands::MineSkills,
        "maintain" => Cli::Commands::Maintain,
        "search" => Cli::Commands::Search,
        "stats" => Cli::Commands::Stats,
        "mcp" => Cli::Commands::Mcp
      }[normalized]
    end

    def print_help
      puts <<~HELP
        llmemory - Inspect llmemory storage

        Usage: llmemory <command> [options] [arguments]

        Commands:
          users                    List users with memory
          short-term USER_ID       Inspect short-term memory (use --list-sessions to list sessions)
          facts USER_ID            List long-term facts (file-based)
          categories USER_ID      List long-term categories (file-based)
          resources USER_ID        List long-term resources (file-based)
          nodes USER_ID            List graph nodes (graph-based)
          edges USER_ID            List graph edges (graph-based)
          graph USER_ID            Export graph (--format dot|json)
          episodes USER_ID         List recorded episodes (episodic memory)
          skills USER_ID           List registered skills (procedural memory)
          working USER_ID SESSION  Show working-memory slots for a session
          forget-log USER_ID       Show audit of forgotten entries
          mine-skills USER_ID      Mine reusable skills from episodes (--register to save)
          maintain USER_ID         Run the cognitive maintenance pass (reflect/mine/expire)
          search USER_ID "query"   Search in memory
          stats [USER_ID]          Show statistics
          mcp [serve]              Start MCP server for LLM agents

        Run 'llmemory <command> --help' for command-specific options.
      HELP
    end
  end
end
