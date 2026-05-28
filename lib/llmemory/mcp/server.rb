# frozen_string_literal: true

require "mcp"
require_relative "authentication"
require_relative "tools/memory_search"
require_relative "tools/memory_save"
require_relative "tools/memory_retrieve"
require_relative "tools/memory_timeline"
require_relative "tools/memory_add_message"
require_relative "tools/memory_consolidate"
require_relative "tools/memory_stats"
require_relative "tools/memory_info"
require_relative "tools/memory_timeline_context"
require_relative "tools/memory_episode_record"
require_relative "tools/memory_episodes"
require_relative "tools/memory_skill_register"
require_relative "tools/memory_skill_report"
require_relative "tools/memory_skills"
require_relative "tools/memory_forget"

module Llmemory
  module MCP
    class Server
      attr_reader :server

      def initialize(name: "llmemory", version: nil)
        @server = ::MCP::Server.new(
          name: name,
          version: version || Llmemory::VERSION,
          instructions: instructions_text,
          tools: all_tools
        )
      end

      def run_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      def run_http(port: 3100, host: "0.0.0.0", ssl_cert: nil, ssl_key: nil)
        require "webrick"

        @http_transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(@server)
        app = build_rack_app(@http_transport)

        webrick_options = {
          Port: port,
          BindAddress: host,
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO),
          AccessLog: []
        }

        # Configure SSL/HTTPS if certificates provided
        use_ssl = ssl_cert && ssl_key
        if use_ssl
          require "webrick/https"
          require "openssl"

          webrick_options[:SSLEnable] = true
          webrick_options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read(ssl_cert))
          webrick_options[:SSLPrivateKey] = OpenSSL::PKey::RSA.new(File.read(ssl_key))
        end

        webrick_server = WEBrick::HTTPServer.new(webrick_options)

        webrick_server.mount_proc "/" do |req, res|
          rack_env = build_rack_env(req)
          status, headers, body = app.call(rack_env)

          res.status = status
          headers.each { |key, value| res[key] = value }
          res.body = body.is_a?(Array) ? body.join : body
        end

        trap("INT") { webrick_server.shutdown }
        trap("TERM") { webrick_server.shutdown }

        protocol = use_ssl ? "https" : "http"
        $stderr.puts "llmemory MCP server listening on #{protocol}://#{host}:#{port}"
        $stderr.puts "Authentication: #{ENV["MCP_TOKEN"] ? "enabled (MCP_TOKEN set)" : "disabled"}"

        webrick_server.start
      ensure
        @http_transport&.close
      end

      # Returns a Rack app for use with custom servers (Puma, etc.)
      def rack_app
        transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(@server)
        build_rack_app(transport)
      end

      private

      def build_rack_app(transport)
        app = ->(env) { transport.handle_request(RackRequest.new(env)) }

        # Wrap with authentication if MCP_TOKEN is set
        if ENV["MCP_TOKEN"]
          app = Authentication.new(app)
        end

        app
      end

      def build_rack_env(req)
        env = {
          "REQUEST_METHOD" => req.request_method,
          "SCRIPT_NAME" => "",
          "PATH_INFO" => req.path,
          "QUERY_STRING" => req.query_string || "",
          "SERVER_NAME" => req.host,
          "SERVER_PORT" => req.port.to_s,
          "HTTP_HOST" => req["Host"],
          "rack.input" => StringIO.new(req.body || ""),
          "rack.url_scheme" => req.ssl? ? "https" : "http"
        }

        # Copy HTTP headers
        req.header.each do |key, values|
          header_key = "HTTP_#{key.upcase.tr("-", "_")}"
          env[header_key] = values.is_a?(Array) ? values.join(", ") : values
        end

        env
      end

      # Simple wrapper to make Rack env look like a Rack request
      class RackRequest
        def initialize(env)
          @env = env
        end

        def env
          @env
        end

        def body
          @env["rack.input"]
        end

        def params
          @params ||= parse_query_string(@env["QUERY_STRING"] || "")
        end

        private

        def parse_query_string(qs)
          qs.split("&").each_with_object({}) do |pair, hash|
            key, value = pair.split("=", 2)
            hash[key] = value if key
          end
        end
      end

      def all_tools
        [
          Tools::MemorySearch,
          Tools::MemorySave,
          Tools::MemoryRetrieve,
          Tools::MemoryTimeline,
          Tools::MemoryTimelineContext,
          Tools::MemoryAddMessage,
          Tools::MemoryConsolidate,
          Tools::MemoryStats,
          Tools::MemoryInfo,
          Tools::MemoryEpisodeRecord,
          Tools::MemoryEpisodes,
          Tools::MemorySkillRegister,
          Tools::MemorySkillReport,
          Tools::MemorySkills,
          Tools::MemoryForget
        ]
      end

      def instructions_text
        <<~INSTRUCTIONS
          llmemory MCP Server - Persistent Memory System for LLM Agents

          This server provides tools to manage persistent memory for users:
          - Search memories by semantic query
          - Save new observations and facts
          - Retrieve context optimized for LLM inference
          - Manage conversation sessions
          - Consolidate conversations into long-term memory

          RECOMMENDED WORKFLOW:
          1. At start of conversation: use memory_retrieve to get relevant context
          2. During conversation: use memory_save for important observations
          3. At end: use memory_consolidate to persist the conversation

          Use memory_info tool for detailed usage guidelines.
        INSTRUCTIONS
      end
    end
  end
end
