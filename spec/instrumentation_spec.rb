# frozen_string_literal: true

RSpec.describe Llmemory::Instrumentation do
  describe ".instrument" do
    it "yields the block and returns its value when no notifier is loaded" do
      hide_const("ActiveSupport::Notifications") if defined?(ActiveSupport::Notifications)
      called = false
      described_class.instrument(:test_event, foo: 1) { called = true }
      expect(called).to be true
    end

    it "is a no-op when called without a block" do
      expect { described_class.instrument(:no_block, foo: 1) }.not_to raise_error
    end
  end

  describe "memory_write events" do
    it "emits memory_write.llmemory when ActiveSupport::Notifications is available" do
      pending "ActiveSupport not in bundle" unless defined?(ActiveSupport::Notifications)

      events = []
      subscriber = ActiveSupport::Notifications.subscribe("memory_write.llmemory") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      begin
        memory = Llmemory::LongTerm::Episodic::Memory.new(user_id: "user_1")
        memory.write(steps: [{ observation: "x", action: "y" }])
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(events).not_to be_empty
      expect(events.first.payload[:memory_type]).to eq("episodic")
      expect(events.first.payload[:user_id]).to eq("user_1")
    end
  end

  describe "memory_forget events" do
    it "emits memory_forget.llmemory with count when ActiveSupport::Notifications is available" do
      pending "ActiveSupport not in bundle" unless defined?(ActiveSupport::Notifications)

      events = []
      subscriber = ActiveSupport::Notifications.subscribe("memory_forget.llmemory") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      begin
        memory = Llmemory::LongTerm::Episodic::Memory.new(user_id: "user_1")
        id = memory.write(steps: [{ observation: "x", action: "y" }])
        memory.forget(ids: [id])
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(events).not_to be_empty
      expect(events.first.payload[:memory_type]).to eq("episodic")
      expect(events.first.payload[:count]).to eq(1)
    end
  end
end
