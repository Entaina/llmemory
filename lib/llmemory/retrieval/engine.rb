# frozen_string_literal: true

require_relative "temporal_ranker"
require_relative "context_assembler"
require_relative "bm25_scorer"
require_relative "mmr_reranker"
require_relative "feedback_store"

module Llmemory
  module Retrieval
    class Engine
      RELEVANCE_THRESHOLD = 0.7
      FEEDBACK_CAP = 5

      def initialize(memory, llm: nil, feedback: nil)
        @memory = memory
        @llm = llm || Llmemory::LLM.client
        @ranker = TemporalRanker.new
        @assembler = ContextAssembler.new
        @bm25_scorer = Bm25Scorer.new
        @mmr_reranker = MmrReranker.new(lambda: Llmemory.configuration.mmr_lambda)
        @feedback = feedback || FeedbackStore.new
      end

      def retrieve_for_inference(user_message, user_id: nil, max_tokens: nil)
        user_id ||= @memory.respond_to?(:user_id) ? @memory.user_id : nil
        search_query = generate_query(user_message)
        ranked = ranked_candidates(search_query, user_id, user_message)
        @assembler.assemble(ranked, max_tokens: max_tokens)
      end

      # Multi-hop retrieval (CoALA: integrating retrieval and reasoning). After
      # each hop, a reasoner inspects what has been retrieved and proposes a
      # follow-up query for the missing piece, enabling multi-hop questions a
      # single retrieval would miss. Candidates accumulate (deduped) across hops.
      #
      # `reasoner` is a callable (user_message, accumulated_candidates, hop) ->
      # next query String, or "DONE"/blank to stop. Defaults to an LLM that
      # proposes the next sub-query. Converges on `max_hops`, "DONE", a blank
      # query, or a repeated query.
      def iterative_retrieve(user_message, user_id: nil, max_tokens: nil, max_hops: 2, reasoner: nil)
        user_id ||= @memory.respond_to?(:user_id) ? @memory.user_id : nil
        reasoner ||= method(:default_followup_query)

        query = generate_query(user_message)
        seen = []
        accumulated = []
        hop = 0

        while hop < max_hops && live_query?(query) && !seen.include?(query)
          seen << query
          accumulated = merge_candidates(accumulated, ranked_candidates(query, user_id, query))
          hop += 1
          break if hop >= max_hops

          query = reasoner.call(user_message, accumulated, hop).to_s.strip
        end

        final = accumulated.sort_by { |c| -(c[:temporal_score] || c[:score] || 0) }
        @assembler.assemble(final, max_tokens: max_tokens)
      end

      # Records that previously-retrieved items were useful or harmful for the
      # agent's task. Repeatedly useful items rank higher in future retrievals;
      # noisy ones are dampened. Item ids come from the candidates returned by
      # the memory's #read / #search_candidates.
      def report_feedback(useful_ids: [], harmful_ids: [], user_id: nil)
        user_id ||= @memory.respond_to?(:user_id) ? @memory.user_id : nil
        Array(useful_ids).each { |id| @feedback.record(user_id, id, 1) }
        Array(harmful_ids).each { |id| @feedback.record(user_id, id, -1) }
        true
      end

      private

      # One retrieval hop: fetch -> hybrid -> relevance filter -> temporal rank
      # -> feedback adjust -> (optional) MMR. Returns ranked candidates.
      def ranked_candidates(search_query, user_id, relevance_text)
        candidates = fetch_candidates(search_query, user_id)
        candidates = apply_hybrid_scoring(candidates, search_query) if Llmemory.configuration.hybrid_search_enabled
        relevant = filter_by_relevance(candidates, relevance_text)
        ranked = @ranker.rank(relevant)
        ranked = apply_feedback(ranked, user_id)
        Llmemory.configuration.mmr_enabled ? @mmr_reranker.rerank(ranked) : ranked
      end

      def live_query?(query)
        !query.nil? && !query.to_s.strip.empty? && query.to_s.strip.upcase != "DONE"
      end

      def merge_candidates(accumulated, additions)
        by_key = {}
        (accumulated + additions).each do |c|
          key = c[:id] || c[:text]
          current = by_key[key]
          if current.nil? || score_of(c) > score_of(current)
            by_key[key] = c
          end
        end
        by_key.values
      end

      def score_of(candidate)
        (candidate[:temporal_score] || candidate[:score] || 0).to_f
      end

      def default_followup_query(user_message, accumulated, _hop)
        context = accumulated.first(10).map { |c| c[:text] }.compact.join("\n")
        prompt = <<~PROMPT
          Question: #{user_message}
          Information retrieved so far:
          #{context}

          If more information is needed to fully answer the question, reply with a
          single short search query for the missing piece. If what was retrieved is
          sufficient, reply with exactly "DONE".
        PROMPT
        @llm.invoke(prompt.strip).to_s.strip
      rescue Llmemory::LLMError
        "DONE"
      end

      def apply_feedback(ranked, user_id)
        weight = Llmemory.configuration.retrieval_feedback_weight.to_f
        return ranked if user_id.nil? || weight <= 0

        adjusted = ranked.map do |c|
          id = c[:id] || c["id"]
          net = id.nil? ? 0 : @feedback.net(user_id, id)
          next c if net.zero?

          base = (c[:temporal_score] || c[:score] || 0).to_f
          c.merge(temporal_score: base * feedback_factor(net, weight))
        end
        adjusted.sort_by { |c| -(c[:temporal_score] || 0) }
      end

      # Maps net feedback to a bounded multiplier in [1 - weight, 1 + weight].
      def feedback_factor(net, weight)
        capped = [[net, -FEEDBACK_CAP].max, FEEDBACK_CAP].min
        1.0 + (weight * (capped.to_f / FEEDBACK_CAP))
      end

      def generate_query(user_message)
        return user_message.to_s if user_message.to_s.length <= 100
        prompt = <<~PROMPT
          Summarize this user message into a short search query (one sentence, under 15 words) to find relevant memories.
          Message: #{user_message}
          Return only the search query.
        PROMPT
        @llm.invoke(prompt.strip).to_s.strip
      rescue Llmemory::LLMError
        user_message.to_s[0..200]
      end

      def fetch_candidates(search_query, user_id)
        return [] unless @memory.respond_to?(:search_candidates)

        raw = @memory.search_candidates(search_query, user_id: user_id, top_k: 20)
        raw.map do |c|
          {
            id: c[:id] || c["id"],
            text: c[:text] || c["text"],
            timestamp: parse_timestamp(c[:timestamp] || c["timestamp"] || c[:created_at] || c["created_at"]),
            score: (c[:score] || c["score"] || 1.0).to_f,
            importance: c[:importance] || c["importance"],
            evergreen: c[:evergreen] || c["evergreen"]
          }
        end
      end

      def parse_timestamp(ts)
        return ts if ts.is_a?(Time)
        return Time.parse(ts.to_s) if ts
        Time.now
      end

      def apply_hybrid_scoring(candidates, query)
        return candidates if candidates.empty?

        scored = @bm25_scorer.score_candidates(query, candidates)
        weight = Llmemory.configuration.bm25_weight.to_f
        weight = 0.3 if weight < 0 || weight > 1

        scored.map do |c|
          vector_score = (c[:score] || c["score"] || 1.0).to_f
          bm25_norm = (c[:normalized_bm25] || 0).to_f
          hybrid = weight * bm25_norm + (1 - weight) * vector_score
          c.merge(score: hybrid)
        end
      end

      def filter_by_relevance(candidates, user_message)
        return candidates if candidates.size <= 5
        user_lower = user_message.to_s.downcase
        candidates.select do |c|
          text = (c[:text] || c["text"]).to_s.downcase
          score = (c[:score] || c["score"] || 1.0).to_f
          next true if score >= RELEVANCE_THRESHOLD
          next true if user_lower.split.any? { |w| w.length > 3 && text.include?(w) }
          score >= 0.5
        end
      end
    end
  end
end
