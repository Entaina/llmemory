# frozen_string_literal: true

module Llmemory
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/llmemory.rake", __dir__)
    end
  end
end
