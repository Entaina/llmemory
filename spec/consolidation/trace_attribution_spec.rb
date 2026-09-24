# frozen_string_literal: true

RSpec.describe Llmemory::Consolidation::TraceAttribution do
  describe ".trace_ids_for_fact" do
    it "picks traces with highest token overlap" do
      traces = [
        { id: "t1", content: "Caroline went to the LGBTQ support group yesterday." },
        { id: "t2", content: "Unrelated weather chat." }
      ]
      ids = described_class.trace_ids_for_fact("LGBTQ support group visit", traces)
      expect(ids).to eq(["t1"])
    end
  end

  describe ".merge_trace_sources" do
    it "adds trace sources without duplicating resource" do
      prov = Llmemory::Provenance.from_resource("r1", method: "fact_extraction")
      merged = described_class.merge_trace_sources(prov, %w[t1 t1 t2])
      types = merged[:sources].map { |s| [s[:type], s[:id]] }
      expect(types).to include(["resource", "r1"], ["trace", "t1"], ["trace", "t2"])
    end
  end
end
