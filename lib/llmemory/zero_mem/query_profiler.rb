# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class QueryProfiler
      TEMPORAL_EN = /\b(before|after|first|last|when|timeline|january|february|march|april|may|june|july|august|september|october|november|december|booking|remind)\b/i
      TEMPORAL_ES = /\b(antes|después|primero|último|ultimo|cuándo|cuando|hora|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|reserva|recuerda)\b/i
      CURRENT_EN = /\b(now|today|current|currently|what is)\b/i
      CURRENT_ES = /\b(ahora|actual|hoy|cuál es|cual es)\b/i
      MULTI_EN = /\b(between|compared to|relationship|and .+ and)\b/i
      MULTI_ES = /\b(relación|relacion|entre|comparado)\b/i
      PROCEDURAL = /\b(export|file|balance|informe|report|saldo|api|endpoint|parameter|arguments)\b/i
      ATTRIBUTE = /\b(identity|who is|what is .+'s|research|researched|looking into)\b/i

      def profile(query, boundary: nil, language: nil)
        text = query.to_s.strip
        lang = language || detect_language(text)
        rule_ids = []
        quoted = text.scan(/"([^"]+)"/).flatten
        keywords = Llmemory::Tokenizer.tokenize(text)
        entities = extract_entities(text, lang)

        temporal = temporal_cues(text, lang)
        rule_ids << "temporal_cues" unless temporal.empty?

        workload = infer_workload(text, lang, entities, temporal, rule_ids)
        answer_type = infer_answer_type(text, lang, rule_ids)
        freshness = workload == :current_state

        boundary_h = normalize_boundary(boundary)
        rule_ids << "boundary_explicit" if boundary_h

        QueryProfile.new(
          subject_entities: entities,
          keywords: keywords,
          quoted_phrases: quoted,
          answer_type: answer_type,
          temporal_cues: temporal,
          aggregation_cues: aggregation_cues(text),
          boundary: boundary_h,
          workload_class: workload,
          freshness_requirement: freshness,
          expected_evidence_count: expected_count(workload, aggregation_cues(text)),
          language: lang,
          rule_ids: rule_ids.uniq
        )
      end

      private

      def detect_language(text)
        text.match?(/[¿¡áéíóúñÁÉÍÓÚÑ]/) || text.match?(TEMPORAL_ES) ? :es : :en
      end

      def extract_entities(text, _lang)
        text.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/).uniq.first(5)
      end

      def temporal_cues(text, lang)
        cues = []
        cues.concat(text.scan(lang == :es ? TEMPORAL_ES : TEMPORAL_EN).flatten)
        cues.concat(text.scan(/\b\d{1,2}:\d{2}\b/))
        cues.concat(text.scan(/\b\d{4}-\d{2}-\d{2}\b/))
        cues.map(&:to_s).uniq
      end

      def aggregation_cues(text)
        text.scan(/\b(all|every|list|cuántos|cuantos|how many)\b/i).flatten.uniq
      end

      def infer_workload(text, lang, entities, temporal, rule_ids)
        if text.match?(PROCEDURAL)
          rule_ids << "procedural_cue"
          return :procedural
        end
        if text.match?(ATTRIBUTE)
          rule_ids << "attribute_fact_cue"
          return :local_fact
        end
        if entities.size >= 2 || text.match?(lang == :es ? MULTI_ES : MULTI_EN)
          rule_ids << "multi_entity"
          return :multi_hop
        end
        if text.match?(lang == :es ? CURRENT_ES : CURRENT_EN)
          rule_ids << "current_state_cue"
          return :current_state
        end
        if temporal.any?
          rule_ids << "temporal_workload"
          return :temporal
        end
        if text.match?(/\b(session|sesión|sesion|conversation|earlier)\b/i)
          rule_ids << "cross_session_cue"
          return :cross_session
        end
        :local_fact
      end

      def infer_answer_type(text, lang, rule_ids)
        down = text.downcase
        if down.match?(/\b(when|hora|time|fecha|date)\b/)
          rule_ids << "answer_datetime"
          return :datetime
        end
        if down.match?(/\b(how many|cuánt|cuant|number|número|numero)\b/)
          rule_ids << "answer_number"
          return :number
        end
        if down.match?(/\b(where|dónde|donde|place|address|dirección|direccion)\b/)
          rule_ids << "answer_place"
          return :place
        end
        if down.match?(/\b(yes|no|true|false|sí|si)\b/)
          rule_ids << "answer_boolean"
          return :boolean
        end
        if down.match?(/\b(list|which files|qué archivos|que archivos)\b/)
          rule_ids << "answer_list"
          return :list
        end
        :free_text
      end

      def expected_count(workload, aggregation_cues = [])
        return [3, Llmemory.configuration.zero_mem_max_top_k].min if aggregation_cues.any?

        case workload
        when :multi_hop then 3
        when :procedural then 2
        when :temporal then 2
        else 1
        end
      end

      def normalize_boundary(boundary)
        return nil if boundary.nil?

        b = boundary.is_a?(Hash) ? boundary.transform_keys(&:to_sym) : { session_id: boundary }
        b.compact
      end
    end
  end
end
