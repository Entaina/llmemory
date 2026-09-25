# frozen_string_literal: true

require_relative "scorers/locomo_f1"
require_relative "scorers/substring_em"
require_relative "scorers/tool_call"
require_relative "scorers/arena_match"
require_relative "judge_llm"

module LocalBenchmark
  module Report
    module_function

    def enrich(report, bench:, judge: nil, use_judge: false, eval: nil)
      rows = Array(report[:rows])
      bench_scores = if eval.to_s == "context"
                       context_bench_metrics(rows, report)
                     else
                       bench_metrics(bench, rows, judge: judge, use_judge: use_judge)
                     end
      out = report.merge(
        bench: bench,
        bench_scores: bench_scores,
        disclaimer: disclaimer_for(bench, use_judge: use_judge, eval: eval)
      )
      out[:eval] = eval.to_s if eval
      out
    end

    def context_bench_metrics(rows, report)
      {
        context_hit: context_hit_aggregate(rows),
        localization: report.dig(:means, :localization) || {},
        extraction_yield: extraction_yield_aggregate(rows)
      }
    end

    def bench_metrics(bench, rows, judge:, use_judge:)
      case bench.to_s
      when "locomo"
        {
          locomo_f1: Scorers::LoCoMoF1.aggregate(rows),
          retrieval_hit: retrieval_hit_aggregate(rows),
          extraction_yield: extraction_yield_aggregate(rows),
          hits_converted: hits_converted_aggregate(rows, bench)
        }
      when "longmemeval", "memoryagentbench", "groupmembench"
        scores = {
          substring_em: Scorers::SubstringEM.aggregate(rows),
          retrieval_hit: retrieval_hit_aggregate(rows),
          extraction_yield: extraction_yield_aggregate(rows),
          hits_converted: hits_converted_aggregate(rows, bench)
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
      when "memory_arena"
        {
          arena_match: Scorers::ArenaMatch.aggregate(rows),
          substring_em: Scorers::SubstringEM.aggregate(rows)
        }
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

        j.constraint_consistent?(
          question: row[:query_text].to_s,
          prediction: row[:prediction],
          constraints: constraints,
          reference: row[:gold_answer]
        ) ? 1.0 : 0.0
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
          memory_context: meta["memory_context"],
          rubric: meta["rubric"],
          memory_policy: meta["memory_policy"]
        ) ? 1.0 : 0.0
      end
      { mean: mean(scored), count: scored.size }
    end

    def extraction_yield_aggregate(rows)
      samples = rows.filter_map { |r| r[:extraction_yield] || r["extraction_yield"] }
      return { mean_items_per_session: nil, parse_failures: 0, count: 0 } if samples.empty?

      sessions = samples.sum { |s| s[:consolidate_sessions].to_i }
      items = samples.sum { |s| s[:items_added].to_i }
      empty = samples.sum { |s| s[:empty_extractions].to_i }
      parse_failures = samples.sum { |s| s[:parse_failures].to_i }
      {
        mean_items_per_session: sessions.positive? ? items.to_f / sessions : nil,
        empty_extractions: empty,
        parse_failures: parse_failures,
        count: samples.size
      }
    end

    def hits_converted_aggregate(rows, bench)
      scored = rows.filter_map do |row|
        hit = row[:retrieval_hit]
        next unless hit == true

        f1 = row.dig(:answer, :f1)
        em = row.dig(:answer, :exact_match)
        judge = row[:llm_judge]
        case bench.to_s
        when "locomo"
          f1.to_f > 0.2
        when "longmemeval", "memoryagentbench", "groupmembench"
          Scorers::SubstringEM.score_row(row).to_f.positive? || judge.to_f.positive?
        else
          f1.to_f > 0.2
        end
      end
      hits = rows.count { |r| r[:retrieval_hit] == true }
      return { rate: nil, hits: 0, converted: 0 } if hits.zero?

      { rate: scored.count(true).to_f / hits, hits: hits, converted: scored.count(true) }
    end

    def retrieval_hit_aggregate(rows)
      hits = rows.map { |r| r[:retrieval_hit] }.compact
      return { mean: nil, count: 0, not_applicable: rows.size - hits.size } if hits.empty?

      {
        mean: hits.count(true).to_f / hits.size,
        count: hits.size,
        not_applicable: rows.count { |r| r[:retrieval_hit].nil? }
      }
    end

    def context_hit_aggregate(rows)
      hits = rows.map { |r| r[:context_hit] || r[:retrieval_hit] }.compact
      return { mean: nil, count: 0, not_applicable: rows.size - hits.size } if hits.empty?

      {
        mean: hits.count(true).to_f / hits.size,
        count: hits.size,
        not_applicable: rows.count { |r| (r[:context_hit] || r[:retrieval_hit]).nil? }
      }
    end

    def mean(values)
      vals = Array(values).compact
      return nil if vals.empty?

      vals.sum / vals.size
    end

    def disclaimer_for(bench, use_judge: false, eval: nil)
      parts = ["Local LM Studio run; not comparable to cloud paper numbers."]
      if eval.to_s == "context"
        parts << "Context-only eval: context_hit (no LLM reader or judge)."
        return parts.join(" ")
      end
      parts << "LLM-as-judge uses the same local model." if use_judge
      parts << "LoCoMo F1 follows snap-research token F1 protocol." if bench.to_s == "locomo"
      parts.join(" ")
    end
  end
end
