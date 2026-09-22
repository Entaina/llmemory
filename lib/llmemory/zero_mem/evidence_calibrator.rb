# frozen_string_literal: true

require "digest"

module Llmemory
  module ZeroMem
    class EvidenceCalibrator
      CONFLICT_PATTERNS = [
        /\btalla\s+es\s+([A-Z])\b/i,
        /\bsize\s+is\s+([A-Z])\b/i
      ].freeze

      def initialize(storage)
        @storage = storage
      end

      def calibrate(user_id:, traces:, profile:, current_trace_id: nil, as_of: Time.now,
                    fusion_rows: nil, seed_ids: nil, closure_ids: nil)
        excluded = []
        kept = []

        Array(traces).each do |t|
          reason = exclusion_reason(user_id, t, profile, current_trace_id, as_of)
          if reason
            excluded << { id: t.id, reason: reason }
            next
          end

          kept << t
        end

        deduped, dup_excluded = dedupe_by_content(kept, fusion_rows)
        excluded.concat(dup_excluded)

        conflict_ids = detect_conflicts(deduped)
        ordered = sort_traces(deduped, profile, as_of, fusion_rows: fusion_rows)

        {
          traces: ordered,
          excluded: excluded,
          conflict_trace_ids: conflict_ids,
          seed_ids: Array(seed_ids).map(&:to_s),
          closure_ids: Array(closure_ids).map(&:to_s)
        }
      end

      private

      def exclusion_reason(user_id, trace, profile, current_trace_id, as_of)
        return :wrong_tenant unless trace.user_id == user_id.to_s
        return :archived unless trace.active?
        return :current_query if current_trace_id && trace.id == current_trace_id.to_s
        return :outside_boundary unless boundary_match?(trace, profile.boundary)
        return :hash_mismatch unless sha_ok?(trace)
        return :stale_state unless current_state_ok?(user_id, trace, profile, as_of)

        nil
      end

      def boundary_match?(trace, boundary)
        return true unless boundary

        ok = true
        ok &&= (trace.session_id == boundary[:session_id].to_s) if boundary[:session_id]
        ok &&= (trace.boundary_id == boundary[:boundary_id].to_s) if boundary[:boundary_id]
        ok
      end

      def sha_ok?(trace)
        Digest::SHA256.hexdigest(trace.content) == trace.content_sha256
      end

      def current_state_ok?(user_id, trace, profile, as_of)
        return true unless profile.workload_class == :current_state

        links = @storage.state_links_for(user_id, state_attribute_key(trace))
        return true if links.empty?

        current_id = @storage.current_state_trace_id(user_id, state_attribute_key(trace), as_of: as_of)
        return true if current_id.nil?

        trace.id == current_id.to_s || links.any? { |l| l.trace_id == trace.id }
      end

      def state_attribute_key(trace)
        down = trace.content.downcase
        return "talla" if down.include?("talla")
        return "size" if down.include?("size")

        "state:#{trace.session_id}"
      end

      def dedupe_by_content(traces, fusion_rows)
        by_hash = traces.group_by(&:content_sha256)
        kept = []
        excluded = []
        by_hash.each do |hash, group|
          if group.size == 1
            kept << group.first
            next
          end

          winner = pick_winner(group, fusion_rows)
          kept << winner
          group.each do |t|
            next if t.id == winner.id

            excluded << { id: t.id, reason: :duplicate_content, content_sha256: hash }
          end
        end
        [kept, excluded]
      end

      def pick_winner(group, fusion_rows)
        scores = Array(fusion_rows).each_with_object({}) do |r, acc|
          acc[r[:trace_id].to_s] = r
        end
        group.max_by do |t|
          row = scores[t.id]
          [row ? row[:final].to_f : 0.0, t.occurred_at.to_f]
        end
      end

      def detect_conflicts(traces)
        buckets = Hash.new { |h, k| h[k] = [] }
        traces.each do |t|
          CONFLICT_PATTERNS.each do |pat|
            m = t.content.match(pat)
            next unless m

            buckets[pat.source] << { id: t.id, value: m[1].upcase }
          end
        end

        conflict_ids = []
        buckets.each_value do |entries|
          values = entries.map { |e| e[:value] }.uniq
          next if values.size <= 1

          conflict_ids.concat(entries.map { |e| e[:id] })
        end
        conflict_ids.uniq
      end

      def sort_traces(traces, profile, as_of, fusion_rows: nil)
        scores = Array(fusion_rows).each_with_object({}) do |r, acc|
          acc[r[:trace_id].to_s] = r[:final].to_f
        end

        if profile.freshness_requirement || profile.workload_class == :current_state
          traces.sort_by do |t|
            [-t.occurred_at.to_f, -scores.fetch(t.id, 0.0), subject_rank(t, profile)]
          end
        else
          traces.sort_by do |t|
            [-scores.fetch(t.id, 0.0), subject_rank(t, profile), -t.occurred_at.to_f]
          end
        end
      end

      def subject_rank(trace, profile)
        down = trace.content.downcase
        hits = profile.subject_entities.count { |e| down.include?(e.downcase) }
        -hits
      end
    end
  end
end
