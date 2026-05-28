# frozen_string_literal: true

# Demo de las capacidades cognitivas (CoALA) de llmemory:
# working memory, acción de reasoning, memoria episódica, reflexión,
# memoria procedural (skills), provenance, retrieval adaptativo,
# iterative retrieval y forgetting con auditoría.
#
# Es autónomo y NO requiere red: usa un LLM y un reasoner falsos para las
# partes que normalmente llamarían a un modelo. Ejecutar desde la raíz:
#   bundle exec ruby examples/cognitive_memory.rb

require "bundler/setup"
require "llmemory"

USER = "demo_user"

# LLM falso y determinista para que el ejemplo corra sin API key.
class FakeLLM
  def invoke(prompt)
    case prompt
    when /higher-order insights/i, /reflect/i
      '[{"content": "Rolling back on deploy failure reliably restores service", "confidence": 0.85}]'
    when /next step/i
      "Open the rollback runbook and verify the previous revision."
    else
      "DONE"
    end
  end
end

llm = FakeLLM.new

def section(title)
  puts "\n== #{title} =="
end

# 1) Working memory + reasoning action ---------------------------------------
section("Working memory + reasoning action")
wm = Llmemory::WorkingMemory.new(user_id: USER, session_id: "trip")
wm.goals = ["recover the failing deployment"]
wm.last_observation = "the latest deploy is returning 500s"
wm.set(:severity, "high")

Llmemory::Actions::Reason.call(
  working_memory: wm,
  template: "Goal: {{goals}}. Observation: {{last_observation}}. What is the next step?",
  into: :intermediate_reasoning,
  llm: llm
)
puts "goals:        #{wm.goals.inspect}"
puts "custom slots: #{wm.custom_slots.inspect}"
puts "reasoning ->  #{wm.intermediate_reasoning}"

# 2) Episodic memory ----------------------------------------------------------
section("Episodic memory")
episodic = Llmemory::LongTerm::Episodic::Memory.new(user_id: USER)
episodic.record_episode(
  steps: [{ observation: "deploy failed", action: "rolled back", result: "service restored" }],
  outcome: "recovered", importance: 0.8
)
episodic.record_episode(
  steps: [{ observation: "deploy failed again", action: "rolled back", result: "service restored" }],
  outcome: "recovered", importance: 0.7
)
puts "episodes recorded: #{episodic.count}"
puts "most recent:       #{episodic.recent_episodes(limit: 1).first.summary}"

# 3) Reflection: episodic -> semantic (with provenance) ----------------------
section("Reflection (episodic -> semantic)")
semantic = Llmemory::LongTerm::FileBased::Memory.new(
  user_id: USER, storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new, llm: llm
)
Llmemory::Reflection::Reflector.new(episodic: episodic, semantic: semantic, llm: llm).reflect(window: 10)
insight = semantic.storage.get_all_items(USER).first
puts "insight:    #{insight[:content]}"
puts "provenance: #{insight[:provenance].slice(:method, :sources, :confidence).inspect}"

# 4) Procedural memory (skill library) + outcomes ----------------------------
section("Procedural memory (skills)")
skills = Llmemory::LongTerm::Procedural::Memory.new(user_id: USER)
rollback = skills.register_skill(
  name: "rollback", description: "revert a bad deploy",
  body: "kubectl rollout undo deployment/$1", kind: "code"
)
skills.register_skill(name: "scale-up", description: "add replicas", body: "kubectl scale ...", kind: "code")
skills.report_outcome(rollback, success: true)
skills.report_outcome(rollback, success: true)
puts "skills:       #{skills.count}"
puts "best match:   #{skills.find_skill('revert deploy').name}"
puts "ranked by utility (importance = success rate):"
skills.search_candidates("kubectl").each { |c| puts "  - #{c[:importance].round(2)}  #{c[:text].lines.first.strip}" }

# 5) Uniform interface (MemoryModule) ----------------------------------------
section("Uniform interface (read/list/stats)")
puts "episodic.stats:   #{episodic.stats.inspect}"
puts "skills.stats:     #{skills.stats.inspect}"
puts "semantic.stats:   #{semantic.stats.inspect}"

# 6) Adaptive retrieval feedback ---------------------------------------------
section("Adaptive retrieval feedback")
feedback = Llmemory::Retrieval::FeedbackStore.new(store: Llmemory::ShortTerm::Stores::MemoryStore.new)
engine = Llmemory::Retrieval::Engine.new(skills, llm: llm, feedback: feedback)
candidates = skills.read("kubectl", limit: 5)
engine.report_feedback(useful_ids: [candidates.first[:id]])
puts "recorded feedback for skill id=#{candidates.first[:id]} -> net #{feedback.net(USER, candidates.first[:id])}"

# 7) Iterative (multi-hop) retrieval -----------------------------------------
section("Iterative retrieval (multi-hop)")
hops = ["rollback", "DONE"]
context = engine.iterative_retrieve(
  "how do I recover a failed deploy",
  max_hops: 3,
  reasoner: ->(_q, _acc, _hop) { hops.shift }
)
puts context.lines.first(3).join

# 8) Forgetting with audit ----------------------------------------------------
section("Forgetting with audit")
removed = skills.forget(ids: [rollback], reason: "deprecated runbook")
puts "removed: #{removed}, skills now: #{skills.count}"
puts "audit:   #{skills.forget_log.entries(USER).last.slice(:memory_type, :ids, :reason).inspect}"

puts "\nDone."
