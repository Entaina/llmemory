# frozen_string_literal: true

require_relative "scorers/locomo_f1"
require_relative "scorers/substring_em"
require_relative "scorers/tool_call"
require_relative "judge_llm"

module LocalBenchmark
  module Report
    module_function

    def enrich(report, bench:, judge: nil, use_judge: false)
      rows = Array(report[:rows])
      bench_scores = bench_metrics(bench, rows, judge: judge, use_judge: use_judge)
      report.merge(
        bench: bench,
        bench_scores: bench_scores,
        disclaimer: disclaimer_for(bench, use_judge: use_judge)
      )
    end

    def bench_metrics(bench, rows, judge:, use_judge:)
      case bench.to_s
      when "locomo"
        {
          locomo_f1: Scorers::LoCoMoF1.aggregate(rows),
          retrieval_hit: retrieval_hit_aggregate(rows)
        }
      when "longmemeval", "memoryagentbench", "groupmembench", "memory_arena"
        scores = {
          substring_em: Scorers::SubstringEM.aggregate(rows),
          retrieval_hit: retrieval_hit_aggregate(rows)
        }
        scores[:llm_judge] = llm_judge_scores(rows, judge) if use_judge
        scores
      when "locomo_plus"
        scores = { constraint_judge: constraint_scores(rows, judge) }
        scores[:llm_judge] = llm_judge_scores(rows, judge) if use_judge
        scores
      when "memsyco"
        { memsyco_judge: memsyco_scores(rows, judge) }
      when "mem2act"
        mem2act_scores(rows)
      when "fixtures"
        { substring_em: Scorers::SubstringEM.aggregate(rows) }
      else
        { substring_em: Scorers::SubstringEM.aggregate(rows) }
      end
    end

    def mem2act_scores(rows)
      tool_acc = []
      param_f1 = []
      rows.each do |row|
        meta = row[:metadata] || {}
        next unless meta["tool_name"]

        tool_acc << Scorers::ToolCall.tool_accuracy(row[:prediction], meta["tool_name"])
        param_f1 << Scorers::ToolCall.param_f1(row[:prediction], meta["tool_arguments"] || {})
      end
      {
        tool_accuracy: mean(tool_acc),
        param_f1: mean(param_f1),
        count: tool_acc.size
      }
    end

    def llm_judge_scores(rows, judge)
      j = judge || JudgeLLM.new
      scored = rows.filter_map do |row|
        next unless row[:gold_answer]

        j.correct?(question: row[:query_text].to_s, prediction: row[:prediction], reference: row[:gold_answer]) ? 1.0 : 0.0
      end
      { mean: mean(scored), count: scored.size }
    end

    def constraint_scores(rows, judge)
      j = judge || JudgeLLM.new
      scored = rows.filter_map do |row|
        meta = row[:metadata] || {}
        constraints = meta["constraints"]
        next unless constraints

        j.constraint_consistent?(question: row[:gold_answer].to_s, prediction: row[:prediction], constraints: constraints) ? 1.0 : 0.0
      end
      { mean: mean(scored), count: scored.size }
    end

    def memsyco_scores(rows, judge)
      j = judge || JudgeLLM.new
      scored = rows.filter_map do |row|
        meta = row[:metadata] || {}
        next unless row[:gold_answer]

        j.mem_syco_task(
          task_name: row[:question_type],
          question: row[:query_text].to_s,
          prediction: row[:prediction],
          reference: row[:gold_answer],
          memory_context: meta["memory_context"]
        ) ? 1.0 : 0.0
      end
      { mean: mean(scored), count: scored.size }
    end

    def retrieval_hit_aggregate(rows)
      hits = rows.filter_map { |r| r[:retrieval_hit] }
      return { mean: nil, count: 0 } if hits.empty?

      { mean: hits.count(true).to_f / hits.size, count: hits.size }
    end

    def mean(values)
      vals = Array(values).compact
      return nil if vals.empty?

      vals.sum / vals.size
    end

    def disclaimer_for(bench, use_judge:)
      parts = ["Local LM Studio run; not comparable to cloud paper numbers."]
      parts << "LLM-as-judge uses the same local model." if use_judge
      parts << "LoCoMo F1 follows snap-research token F1 protocol." if bench.to_s == "locomo"
      parts.join(" ")
    end
  end
end
