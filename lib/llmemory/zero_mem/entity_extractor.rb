# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EntityExtractor
      def extract(_text)
        raise NotImplementedError
      end

      def generative?
        false
      end

      def name
        self.class.name.split("::").last.downcase
      end

      def version
        "1"
      end
    end
  end
end
