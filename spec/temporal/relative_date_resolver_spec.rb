# frozen_string_literal: true

RSpec.describe Llmemory::Temporal::RelativeDateResolver do
  subject(:resolver) { described_class.new }

  it "resolves yesterday from anchor time" do
    result = resolver.resolve(
      "Caroline went to a LGBTQ support group yesterday.",
      reference_time: Time.utc(2023, 5, 8, 13, 56)
    )
    expect(result[:event_date]).to eq("2023-05-07")
    expect(result[:content]).to include("7 May 2023")
  end

  it "resolves last week as anchor minus seven days" do
    result = resolver.resolve("Met friends last week.", reference_time: Time.utc(2023, 6, 9))
    expect(result[:event_date]).to eq("2023-06-02")
  end

  it "annotates next month with the full month name" do
    result = resolver.resolve(
      "We're thinking about going camping next month.",
      reference_time: Time.utc(2023, 5, 25)
    )
    expect(result[:event_date]).to eq("2023-06-01")
    expect(result[:content]).to include("next month (June 2023)")
  end

  it "annotates a month and day with the year of the message" do
    result = resolver.resolve(
      "Reporting can validate fit against the same standard before July 18.",
      reference_time: Time.utc(2025, 7, 10)
    )
    expect(result[:event_date]).to eq("2025-07-18")
    expect(result[:content]).to include("July 18 (2025-07-18)")
  end

  it "does not relabel a named month-day with the date of today" do
    result = resolver.resolve(
      "Finance Ops should stamp the owner today, against the July 18 baseline.",
      reference_time: Time.utc(2025, 7, 17)
    )
    expect(result[:event_date]).to eq("2025-07-17")
    expect(result[:content]).to include("July 18 (2025-07-18)")
    expect(result[:content]).not_to include("July 18 (2025-07-17)")
  end

  it "leaves an explicit calendar year untouched" do
    result = resolver.resolve(
      "The framework must be finalized before July 19, 2025.",
      reference_time: Time.utc(2025, 7, 10)
    )
    expect(result[:content]).to eq("The framework must be finalized before July 19, 2025.")
  end

  it "annotates last year with calendar year" do
    result = resolver.resolve("Caroline moved last year.", reference_time: Time.utc(2023, 5, 8))
    expect(result[:content]).to include("last year (2022)")
  end
end

