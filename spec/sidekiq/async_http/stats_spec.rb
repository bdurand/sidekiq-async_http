# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::Stats do
  let(:stats) { described_class.new }

  describe "#record_request" do
    it "records request with duration" do
      stats.record_request(0.5)
      stats.record_request(1.5)

      totals = stats.get_totals
      expect(totals["requests"]).to eq(2)
      expect(totals["duration"]).to eq(2.0)
    end

    it "records to hourly stats" do
      stats.record_request(0.5)

      hourly = stats.get_hourly_stats
      expect(hourly["requests"]).to eq(1)
      expect(hourly["duration"]).to eq(0.5)
    end
  end

  describe "#record_error" do
    it "increments error count" do
      stats.record_error
      stats.record_error

      totals = stats.get_totals
      expect(totals["errors"]).to eq(2)
    end

    it "records to hourly stats" do
      stats.record_error

      hourly = stats.get_hourly_stats
      expect(hourly["errors"]).to eq(1)
    end
  end

  describe "#record_refused" do
    it "increments refused count" do
      stats.record_refused
      stats.record_refused

      totals = stats.get_totals
      expect(totals["refused"]).to eq(2)
    end

    it "records to hourly stats" do
      stats.record_refused

      hourly = stats.get_hourly_stats
      expect(hourly["refused"]).to eq(1)
    end
  end

  describe "#update_inflight" do
    it "updates inflight count for current process" do
      stats.update_inflight(5)

      all_inflight = stats.get_all_inflight
      expect(all_inflight.values.first).to eq(5)
    end

    it "overwrites previous value" do
      stats.update_inflight(5)
      stats.update_inflight(3)

      all_inflight = stats.get_all_inflight
      expect(all_inflight.values.first).to eq(3)
    end
  end

  describe "#get_hourly_stats" do
    it "returns stats for current hour by default" do
      stats.record_request(0.5)
      stats.record_error
      stats.record_refused

      hourly = stats.get_hourly_stats
      expect(hourly["requests"]).to eq(1)
      expect(hourly["duration"]).to eq(0.5)
      expect(hourly["errors"]).to eq(1)
      expect(hourly["refused"]).to eq(1)
    end

    it "returns stats for specific time" do
      # Record some stats
      stats.record_request(0.5)

      # Get stats for a different hour (should be empty)
      past_time = Time.now - 3600
      hourly = stats.get_hourly_stats(past_time)
      expect(hourly["requests"]).to eq(0)
    end

    it "returns zero values when no data" do
      hourly = stats.get_hourly_stats
      expect(hourly["requests"]).to eq(0)
      expect(hourly["duration"]).to eq(0.0)
      expect(hourly["errors"]).to eq(0)
      expect(hourly["refused"]).to eq(0)
    end
  end

  describe "#get_totals" do
    it "returns all totals" do
      stats.record_request(0.5)
      stats.record_request(1.5)
      stats.record_error
      stats.record_refused

      totals = stats.get_totals
      expect(totals["requests"]).to eq(2)
      expect(totals["duration"]).to eq(2.0)
      expect(totals["errors"]).to eq(1)
      expect(totals["refused"]).to eq(1)
    end

    it "returns zero values when no data" do
      totals = stats.get_totals
      expect(totals["requests"]).to eq(0)
      expect(totals["duration"]).to eq(0.0)
      expect(totals["errors"]).to eq(0)
      expect(totals["refused"]).to eq(0)
    end
  end

  describe "#get_all_inflight" do
    it "returns all inflight counts" do
      stats.update_inflight(5)

      all_inflight = stats.get_all_inflight
      expect(all_inflight).to be_a(Hash)
      expect(all_inflight.values).to include(5)
    end

    it "returns empty hash when no inflight data" do
      all_inflight = stats.get_all_inflight
      expect(all_inflight).to eq({})
    end
  end

  describe "#get_total_inflight" do
    it "sums all inflight counts" do
      stats.update_inflight(5)

      total = stats.get_total_inflight
      expect(total).to eq(5)
    end

    it "returns 0 when no inflight data" do
      total = stats.get_total_inflight
      expect(total).to eq(0)
    end
  end

  describe "#reset!" do
    it "clears all stats" do
      stats.record_request(0.5)
      stats.record_error
      stats.record_refused
      stats.update_inflight(5)

      stats.reset!

      totals = stats.get_totals
      expect(totals["requests"]).to eq(0)
      expect(totals["errors"]).to eq(0)
      expect(totals["refused"]).to eq(0)

      hourly = stats.get_hourly_stats
      expect(hourly["requests"]).to eq(0)

      all_inflight = stats.get_all_inflight
      expect(all_inflight).to eq({})
    end
  end

  describe "Redis integration" do
    it "stores and retrieves data from Redis" do
      stats.record_request(0.5)
      stats.record_error
      stats.record_refused

      totals = stats.get_totals
      expect(totals["requests"]).to eq(1)
      expect(totals["errors"]).to eq(1)
      expect(totals["refused"]).to eq(1)
    end

    it "stores hourly data in Redis" do
      stats.record_request(0.5)

      hourly = stats.get_hourly_stats
      expect(hourly["requests"]).to eq(1)
      expect(hourly["duration"]).to eq(0.5)
    end

    it "stores inflight data in Redis" do
      stats.update_inflight(5)

      all_inflight = stats.get_all_inflight
      expect(all_inflight.values).to include(5)
    end
  end
end
