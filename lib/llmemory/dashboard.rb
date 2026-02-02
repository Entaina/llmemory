# frozen_string_literal: true

unless defined?(Rails)
  raise LoadError, "llmemory/dashboard requires Rails. " \
    "Use the CLI for non-Rails environments: `llmemory --help`"
end

require_relative "dashboard/engine"
