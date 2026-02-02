# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sidekiq::AsyncHttp::ExternalStorage do
  let(:temp_dir) { Dir.mktmpdir("external_storage_test") }

  before do
    Sidekiq::AsyncHttp.configure do |config|
      config.register_payload_store(:test, :file, directory: temp_dir)
      config.payload_store_threshold = 100
    end
  end

  after do
    Sidekiq::AsyncHttp.reset_configuration!
    FileUtils.rm_rf(temp_dir)
  end

  describe ".store" do
    it "returns original hash when below threshold" do
      small_data = {"status" => 200}
      result = described_class.store(small_data)
      expect(result).to eq(small_data)
    end

    it "stores externally and returns reference when above threshold" do
      large_data = {"body" => "x" * 200}
      result = described_class.store(large_data)

      expect(result).not_to eq(large_data)
      expect(result).to have_key("$ref")
      expect(result["$ref"]["store"]).to eq("test")
      expect(result["$ref"]["key"]).to match(/^[0-9a-f-]{36}$/)
    end

    it "returns original hash when no payload store is configured" do
      Sidekiq::AsyncHttp.reset_configuration!
      large_data = {"body" => "x" * 200}
      result = described_class.store(large_data)
      expect(result).to eq(large_data)
    end
  end

  describe ".storage_ref?" do
    it "returns true for storage references" do
      ref_data = {"$ref" => {"store" => "test", "key" => "abc123"}}
      expect(described_class.storage_ref?(ref_data)).to be true
    end

    it "returns false for regular hashes" do
      regular_data = {"status" => 200}
      expect(described_class.storage_ref?(regular_data)).to be false
    end

    it "returns false for non-hashes" do
      expect(described_class.storage_ref?(nil)).to be false
      expect(described_class.storage_ref?(123)).to be false
      expect(described_class.storage_ref?("string")).to be false
    end
  end

  describe ".fetch" do
    it "fetches stored data" do
      large_data = {"body" => "x" * 200}
      ref_data = described_class.store(large_data)

      result = described_class.fetch(ref_data)
      expect(result).to eq(large_data)
    end

    it "raises error when store is not registered" do
      ref_data = {"$ref" => {"store" => "nonexistent", "key" => "abc123"}}

      expect { described_class.fetch(ref_data) }.to raise_error(
        RuntimeError,
        /Payload store 'nonexistent' not registered/
      )
    end

    it "raises error when payload is not found" do
      ref_data = {"$ref" => {"store" => "test", "key" => "nonexistent-key"}}

      expect { described_class.fetch(ref_data) }.to raise_error(
        RuntimeError,
        /Stored payload not found/
      )
    end
  end

  describe ".delete" do
    it "deletes stored payload" do
      large_data = {"body" => "x" * 200}
      ref_data = described_class.store(large_data)

      key = ref_data["$ref"]["key"]
      store = Sidekiq::AsyncHttp.configuration.payload_store

      expect(store.exists?(key)).to be true

      described_class.delete(ref_data)
      expect(store.exists?(key)).to be false
    end

    it "is idempotent" do
      large_data = {"body" => "x" * 200}
      ref_data = described_class.store(large_data)

      described_class.delete(ref_data)
      expect { described_class.delete(ref_data) }.not_to raise_error
    end

    it "does nothing for non-reference hashes" do
      regular_data = {"status" => 200}
      expect { described_class.delete(regular_data) }.not_to raise_error
    end

    it "handles nil gracefully" do
      expect { described_class.delete(nil) }.not_to raise_error
    end
  end

  describe "round trip" do
    it "stores and fetches Response data" do
      response = Sidekiq::AsyncHttp::Response.new(
        status: 200,
        headers: {"content-type" => "application/json"},
        body: "x" * 200,
        duration: 0.1,
        request_id: "test-id",
        url: "http://example.com",
        http_method: :get
      )

      original_data = response.as_json
      ref_data = described_class.store(original_data)

      expect(described_class.storage_ref?(ref_data)).to be true

      fetched_data = described_class.fetch(ref_data)
      loaded = Sidekiq::AsyncHttp::Response.load(fetched_data)

      expect(loaded.status).to eq(200)
      expect(loaded.body).to eq("x" * 200)

      described_class.delete(ref_data)
      expect { described_class.fetch(ref_data) }.to raise_error(/Stored payload not found/)
    end

    it "stores and fetches Request data" do
      request = Sidekiq::AsyncHttp::Request.new(
        :post,
        "http://example.com",
        body: "x" * 200,
        headers: {"content-type" => "application/json"}
      )

      original_data = request.as_json
      ref_data = described_class.store(original_data)

      expect(described_class.storage_ref?(ref_data)).to be true

      fetched_data = described_class.fetch(ref_data)
      loaded = Sidekiq::AsyncHttp::Request.load(fetched_data)

      expect(loaded.http_method).to eq(:post)
      expect(loaded.body).to eq("x" * 200)
    end
  end

  describe "migration between stores" do
    let(:old_dir) { Dir.mktmpdir("old_store") }
    let(:new_dir) { Dir.mktmpdir("new_store") }

    after do
      FileUtils.rm_rf(old_dir)
      FileUtils.rm_rf(new_dir)
    end

    it "reads from old store while writing to new store" do
      # Setup old store and create a stored payload
      Sidekiq::AsyncHttp.configure do |config|
        config.register_payload_store(:old_store, :file, directory: old_dir)
        config.payload_store_threshold = 100
      end

      large_data = {"body" => "x" * 200}
      old_ref_data = described_class.store(large_data)
      expect(old_ref_data["$ref"]["store"]).to eq("old_store")

      # Register new store as default, keeping old store registered
      Sidekiq::AsyncHttp.configure do |config|
        config.register_payload_store(:old_store, :file, directory: old_dir)
        config.register_payload_store(:new_store, :file, directory: new_dir)
        config.payload_store_threshold = 100
      end

      # New writes go to new store
      new_large_data = {"body" => "y" * 200}
      new_ref_data = described_class.store(new_large_data)
      expect(new_ref_data["$ref"]["store"]).to eq("new_store")

      # Can still fetch from old store
      expect(described_class.fetch(old_ref_data)).to eq(large_data)

      # Can fetch from new store
      expect(described_class.fetch(new_ref_data)).to eq(new_large_data)
    end
  end
end
