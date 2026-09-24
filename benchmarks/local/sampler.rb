# frozen_string_literal: true

require "digest"

module LocalBenchmark
  module Sampler
    module_function

    def sample(conversations, bench:, limit: nil, conversations_limit: nil, per_conversation: nil, seed: nil,
               stratify: nil)
      list = conversations.dup

      if stratify.to_s == "category" && bench.to_s == "locomo"
        sample_locomo_stratified(
          list,
          conversations_limit: conversations_limit,
          per_conversation: per_conversation,
          seed: seed
        )
      elsif stratify.to_s == "question_type" && bench.to_s == "longmemeval"
        sample_longmemeval_stratified(list, limit: limit, seed: seed)
      else
        {
          conversations: Canonical.limit_conversations(list, limit: limit),
          sampling: { mode: "limit", seed: seed, limit: limit }
        }
      end
    end

    def max_sessions_for_sample
      raw = ENV["LOCOMO_MAX_SESSIONS"].to_s
      raw = ENV["STEP_MAX_SESSIONS"].to_s if raw.empty?
      raw.empty? ? 0 : raw.to_i
    end

    def evidence_max_session(query)
      Array(query["gold_trace_ids"]).map do |tid|
        m = tid.to_s.match(/\A[Dd](\d+)/)
        m ? m[1].to_i : 999
      end.max || 999
    end

    def sample_locomo_stratified(conversations, conversations_limit:, per_conversation:, seed:)
      rng = rng_for(seed)
      conv_limit = (conversations_limit || 3).to_i
      per_q = (per_conversation || 8).to_i
      categories = [1, 2, 3, 4, 5]
      max_sess = max_sessions_for_sample

      ordered = conversations.sort_by { |c| Array(c["sessions"]).size }
      shuffled = if conv_limit == 1 && per_q <= 4
                   ordered.first(1)
                 else
                   ordered.shuffle(random: rng).first([conv_limit, ordered.size].min)
                 end
      picked_convs = shuffled
      out = []
      selected = []

      picked_convs.each do |conv|
        query_pool = Array(conv["queries"])
        if max_sess.positive?
          query_pool = query_pool.select { |q| evidence_max_session(q) <= max_sess }
        end

        by_cat = Hash.new { |h, k| h[k] = [] }
        query_pool.each do |q|
          cat = (q["category"] || q["category_id"] || 1).to_i
          by_cat[cat] << q
        end

        chosen = []
        categories.each do |cat|
          pool = by_cat[cat]
          next if pool.empty?

          take = [2, pool.size].min
          chosen.concat(pool.shuffle(random: rng).first(take))
        end
        remaining = per_q - chosen.size
        if remaining.positive?
          rest = query_pool - chosen
          chosen.concat(rest.shuffle(random: rng).first(remaining))
        end
        chosen = chosen.uniq.first(per_q).map do |q|
          q = q.dup
          q["evidence_max_session"] = evidence_max_session(q)
          q
        end

        dup = conv.dup
        dup["queries"] = chosen
        dup["step_max_sessions"] = max_sess if max_sess.positive?
        out << dup
        selected << {
          conversation_id: conv["id"],
          query_ids: chosen.map { |q| q["id"] },
          max_sessions: (max_sess if max_sess.positive?)
        }.compact
      end

      {
        conversations: out,
        sampling: {
          mode: "stratify_category",
          seed: seed,
          selected: selected,
          max_sessions: (max_sess if max_sess.positive?)
        }.compact
      }
    end

    def sample_longmemeval_stratified(conversations, limit:, seed:)
      rng = rng_for(seed)
      lim = limit.to_i
      lim = conversations.size if lim <= 0

      by_type = Hash.new { |h, k| h[k] = [] }
      conversations.each do |conv|
        q = Array(conv["queries"]).first
        type = q ? (q["question_type"] || q["type"] || "unknown").to_s : "unknown"
        by_type[type] << conv
      end

      types = by_type.keys.sort
      per_type = [lim / [types.size, 1].max, 1].max
      out = types.flat_map { |type| by_type[type].shuffle(random: rng).first(per_type) }.first(lim)

      {
        conversations: out,
        sampling: {
          mode: "stratify_question_type",
          seed: seed,
          selected: out.map { |c| c["id"] }
        }
      }
    end

    def rng_for(seed)
      if seed.nil? || seed.to_s.empty?
        Random.new
      else
        Random.new(Digest::SHA256.hexdigest(seed.to_s)[0, 8].to_i(16))
      end
    end
  end
end
