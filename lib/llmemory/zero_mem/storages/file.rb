# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../storage"
require_relative "memory"
require_relative "snapshot_codec"
require_relative "../../crypto/field_helpers"

module Llmemory
  module ZeroMem
    module Storages
      class FileStorage
        include Storage
        include Llmemory::Crypto::FieldHelpers

        MUTATORS = %i[
          write_trace archive_trace write_state_link close_open_state_links set_watermark
          write_unit set_open_episode close_episode upsert_entity write_mention
          link_adjacent_traces store_turn_embedding
        ].freeze

        def initialize(base_path: nil, cipher: nil)
          @base_path = File.expand_path(base_path || Llmemory.configuration.long_term_storage_path || "./llmemory_data")
          @cipher = cipher || Llmemory.build_cipher
          @inner = Memory.new
          load!
        end

        Storage.instance_methods(false).each do |method_name|
          next if MUTATORS.include?(method_name)

          define_method(method_name) do |*args, **kwargs, &block|
            @inner.public_send(method_name, *args, **kwargs, &block)
          end
        end

        MUTATORS.each do |method_name|
          define_method(method_name) do |*args, **kwargs, &block|
            result = @inner.public_send(method_name, *args, **kwargs, &block)
            save!
            result
          end
        end

        private

        def snapshot_path
          File.join(@base_path, "zero_mem", "snapshot.json")
        end

        def load!
          path = snapshot_path
          return unless File.file?(path)

          data = read_encrypted_file(path)
          SnapshotCodec.load!(@inner, data)
        end

        def save!
          FileUtils.mkdir_p(File.dirname(snapshot_path))
          write_encrypted_file(snapshot_path, SnapshotCodec.dump(@inner))
        end
      end
    end
  end
end
