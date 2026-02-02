# frozen_string_literal: true

require_relative "lib/llmemory/version"

Gem::Specification.new do |spec|
  spec.name = "llmemory"
  spec.version = Llmemory::VERSION
  spec.authors = ["llmemory"]
  spec.email = [""]

  spec.summary = "Persistent memory system for LLM agents"
  spec.description = "Memory infrastructure for agents: short-term checkpointing, long-term file-based and graph-based memory, retrieval with time decay, and maintenance jobs."
  spec.homepage = "https://github.com/entaina/llmemory"
  spec.required_ruby_version = ">= 3.0.0"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,exe}/**/*", "LICENSE.txt", "README.md"].select { |f| File.file?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "vcr", "~> 6.2"
  spec.add_development_dependency "webmock", "~> 3.18"
end
