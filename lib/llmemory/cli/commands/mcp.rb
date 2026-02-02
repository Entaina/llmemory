# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Mcp < Base
        def option_parser(parser)
          @server_name = "llmemory"
          parser.banner = "Usage: llmemory mcp [serve] [options]"
          parser.on("--name NAME", "Server name (default: llmemory)") { |v| @server_name = v }
          parser.on("-h", "--help", "Show this help") do
            puts parser
            exit
          end
        end

        def execute(argv, _opts)
          action = argv.shift || "serve"

          case action
          when "serve"
            run_server
          when "help", "--help", "-h"
            puts "Usage: llmemory mcp [serve] [options]"
            puts ""
            puts "Options:"
            puts "  --name NAME    Server name (default: llmemory)"
            puts ""
            puts "Starts an MCP (Model Context Protocol) server that exposes llmemory"
            puts "tools for use with LLM agents like Claude Code."
            puts ""
            puts "Example configuration for Claude Code (~/.claude/claude_code_config.json):"
            puts '  {'
            puts '    "mcpServers": {'
            puts '      "llmemory": {'
            puts '        "command": "llmemory",'
            puts '        "args": ["mcp", "serve"]'
            puts '      }'
            puts '    }'
            puts '  }'
          else
            $stderr.puts "Unknown MCP action: #{action}"
            $stderr.puts "Usage: llmemory mcp [serve] [--name NAME]"
            exit 1
          end
        end

        private

        def run_server
          require_relative "../../mcp"

          # Silence stderr to avoid interference with MCP protocol
          # unless debugging is enabled
          unless ENV["LLMEMORY_DEBUG"]
            $stderr.reopen(File::NULL, "w")
          end

          server = Llmemory::MCP::Server.new(name: @server_name)
          server.run_stdio
        end
      end
    end
  end
end
