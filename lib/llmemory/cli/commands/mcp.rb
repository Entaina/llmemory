# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Mcp < Base
        def option_parser(parser)
          @server_name = "llmemory"
          @http_mode = false
          @port = 3100
          @host = "127.0.0.1"
          @ssl_cert = nil
          @ssl_key = nil

          parser.banner = "Usage: llmemory mcp [serve] [options]"
          parser.on("--name NAME", "Server name (default: llmemory)") { |v| @server_name = v }
          parser.on("--http", "Run as HTTP server instead of stdio") { @http_mode = true }
          parser.on("--port PORT", Integer, "HTTP port (default: 3100)") { |v| @port = v }
          parser.on("--host HOST", "HTTP host (default: 127.0.0.1)") { |v| @host = v }
          parser.on("--ssl-cert FILE", "SSL certificate file for HTTPS") { |v| @ssl_cert = v }
          parser.on("--ssl-key FILE", "SSL private key file for HTTPS") { |v| @ssl_key = v }
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
            show_help
          else
            $stderr.puts "Unknown MCP action: #{action}"
            $stderr.puts "Usage: llmemory mcp [serve] [options]"
            exit 1
          end
        end

        private

        def show_help
          puts "Usage: llmemory mcp [serve] [options]"
          puts ""
          puts "Options:"
          puts "  --name NAME      Server name (default: llmemory)"
          puts "  --http           Run as HTTP server instead of stdio"
          puts "  --port PORT      HTTP port (default: 3100)"
          puts "  --host HOST      HTTP host (default: 127.0.0.1)"
          puts "  --ssl-cert FILE  SSL certificate file for HTTPS"
          puts "  --ssl-key FILE   SSL private key file for HTTPS"
          puts ""
          puts "Environment Variables:"
          puts "  MCP_TOKEN      If set, enables token authentication for HTTP mode"
          puts "  LLMEMORY_DEBUG Set to 1 to enable debug output"
          puts ""
          puts "Authentication (HTTP/HTTPS mode only):"
          puts "  When MCP_TOKEN is set, requests must include either:"
          puts "  - Authorization header: 'Bearer <token>' or '<token>'"
          puts "  - Query parameter: '?token=<token>'"
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
          puts ""
          puts "HTTP mode example:"
          puts "  MCP_TOKEN=secret123 llmemory mcp serve --http --port 3100"
          puts ""
          puts "HTTPS mode example:"
          puts "  MCP_TOKEN=secret123 llmemory mcp serve --http --port 443 \\"
          puts "    --ssl-cert /path/to/cert.pem --ssl-key /path/to/key.pem"
        end

        def run_server
          require_relative "../../mcp"

          unless Llmemory::MCP.available?
            $stderr.puts "Error: The 'mcp' gem is required for MCP server functionality."
            $stderr.puts ""
            $stderr.puts "Install it with:"
            $stderr.puts "  gem install mcp"
            $stderr.puts ""
            $stderr.puts "Or add to your Gemfile:"
            $stderr.puts "  gem 'mcp', '~> 0.6'"
            exit 1
          end

          Llmemory.configure { |c| c.shared_memory_stores = true }

          server = Llmemory::MCP::Server.new(name: @server_name)

          if @http_mode
            validate_ssl_options!
            server.run_http(port: @port, host: @host, ssl_cert: @ssl_cert, ssl_key: @ssl_key)
          else
            # Silence stderr to avoid interference with MCP protocol
            # unless debugging is enabled
            unless ENV["LLMEMORY_DEBUG"]
              $stderr.reopen(File::NULL, "w")
            end

            server.run_stdio
          end
        end

        def validate_ssl_options!
          # If one SSL option is provided, both must be provided
          if (@ssl_cert && !@ssl_key) || (!@ssl_cert && @ssl_key)
            $stderr.puts "Error: Both --ssl-cert and --ssl-key must be provided for HTTPS"
            exit 1
          end

          # Validate files exist if SSL is enabled
          if @ssl_cert && @ssl_key
            unless File.exist?(@ssl_cert)
              $stderr.puts "Error: SSL certificate file not found: #{@ssl_cert}"
              exit 1
            end
            unless File.exist?(@ssl_key)
              $stderr.puts "Error: SSL key file not found: #{@ssl_key}"
              exit 1
            end
          end
        end
      end
    end
  end
end
