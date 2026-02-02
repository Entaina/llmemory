# frozen_string_literal: true

module Llmemory
  module Dashboard
    class Engine < ::Rails::Engine
      isolate_namespace Llmemory::Dashboard

      config.root = File.expand_path("..", __FILE__)
    end
  end
end
