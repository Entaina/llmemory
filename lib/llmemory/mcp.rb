# frozen_string_literal: true

module Llmemory
  module MCP
    class << self
      def available?
        @available
      end

      def require_mcp!
        unless available?
          raise LoadError, <<~MSG
            The 'mcp' gem is required for MCP server functionality.
            Install it with: gem install mcp
            Or add to your Gemfile: gem 'mcp', '~> 0.6'
          MSG
        end
      end
    end

    begin
      require "mcp"
      @available = true
      require_relative "mcp/server"
    rescue LoadError
      @available = false
    end
  end
end
