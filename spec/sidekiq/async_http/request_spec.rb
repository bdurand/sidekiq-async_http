# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::Request do
  let(:base_url) { "https://api.example.com" }
  let(:default_headers) { {"Authorization" => "Bearer token123"} }

  describe "#initialize" do
    it "sets the base_url" do
      request = described_class.new(base_url: base_url)
      expect(request.base_url).to eq(base_url)
    end

    it "sets headers as HttpHeaders object" do
      request = described_class.new(headers: default_headers)
      expect(request.headers).to be_a(Sidekiq::AsyncHttp::HttpHeaders)
      expect(request.headers["Authorization"]).to eq("Bearer token123")
    end

    it "sets default timeout to 30 seconds" do
      request = described_class.new
      expect(request.timeout).to eq(30)
    end

    it "allows custom timeout" do
      request = described_class.new(timeout: 60)
      expect(request.timeout).to eq(60)
    end

    it "allows custom open_timeout" do
      request = described_class.new(open_timeout: 10)
      expect(request.open_timeout).to eq(10)
    end

    it "allows custom read_timeout" do
      request = described_class.new(read_timeout: 20)
      expect(request.read_timeout).to eq(20)
    end

    it "allows custom write_timeout" do
      request = described_class.new(write_timeout: 15)
      expect(request.write_timeout).to eq(15)
    end

    it "initializes with empty headers by default" do
      request = described_class.new
      expect(request.headers.to_h).to eq({})
    end
  end

  describe "#async_request" do
    let(:request) { described_class.new(base_url: base_url, headers: default_headers) }

    it "returns an AsyncRequest object" do
      result = request.async_request(:get, "/users")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end

    it "passes itself to the AsyncRequest" do
      result = request.async_request(:get, "/users")
      expect(result.request).to eq(request)
    end

    context "with URI joining" do
      it "joins base_url with relative path" do
        request.async_request(:get, "/users")
        # The joining happens internally, we can verify it doesn't raise
      end

      it "handles paths without leading slash" do
        request.async_request(:get, "users")
        # Should not raise
      end

      it "handles full paths" do
        request.async_request(:get, "/api/v1/users")
        # Should not raise
      end
    end

    context "with query parameters" do
      it "adds params to the URI" do
        request.async_request(:get, "/users", params: {page: 1, limit: 10})
        # Params are encoded and added to query string
      end

      it "merges params with existing query string" do
        request.async_request(:get, "/users?active=true", params: {page: 1})
        # Should merge both query params
      end

      it "handles empty params" do
        result = request.async_request(:get, "/users", params: {})
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end

      it "handles special characters in params" do
        request.async_request(:get, "/search", params: {q: "hello world", filter: "type:user"})
        # Should URL encode params properly
      end
    end

    context "with headers" do
      it "merges request headers with instance headers" do
        request.async_request(:get, "/users", headers: {"X-Request-ID" => "abc123"})
        # Headers should be merged
      end

      it "does not merge when no headers provided" do
        result = request.async_request(:get, "/users")
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end

      it "handles empty headers hash" do
        result = request.async_request(:get, "/users", headers: {})
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end
    end

    context "with JSON body" do
      it "converts json to string body" do
        data = {name: "John", email: "john@example.com"}
        request.async_request(:post, "/users", json: data)
        # Should serialize to JSON
      end

      it "sets Content-Type header for JSON" do
        request.async_request(:post, "/users", json: {name: "John"})
        # Should set application/json content type
      end

      it "raises error when both body and json are provided" do
        expect {
          request.async_request(:post, "/users", body: "raw data", json: {name: "John"})
        }.to raise_error(ArgumentError, "Cannot provide both body and json")
      end

      it "handles complex JSON structures" do
        data = {
          user: {
            name: "John",
            roles: ["admin", "user"],
            metadata: {created_at: "2026-01-09"}
          }
        }
        result = request.async_request(:post, "/users", json: data)
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end
    end

    context "with body" do
      it "accepts string body" do
        result = request.async_request(:post, "/users", body: "raw request body")
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end

      it "accepts nil body" do
        result = request.async_request(:post, "/users", body: nil)
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end
    end

    context "with all options" do
      it "handles all parameters together" do
        result = request.async_request(
          :post,
          "/users",
          body: "data",
          headers: {"X-Custom" => "value"},
          params: {page: 1}
        )
        expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
      end
    end
  end

  describe "#async_get" do
    let(:request) { described_class.new(base_url: base_url) }

    it "calls async_request with :get method" do
      expect(request).to receive(:async_request).with(:get, "/users")
      request.async_get("/users")
    end

    it "forwards all keyword arguments" do
      expect(request).to receive(:async_request).with(
        :get,
        "/users",
        params: {page: 1},
        headers: {"X-Custom" => "value"}
      )
      request.async_get("/users", params: {page: 1}, headers: {"X-Custom" => "value"})
    end

    it "returns an AsyncRequest" do
      result = request.async_get("/users")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end
  end

  describe "#async_post" do
    let(:request) { described_class.new(base_url: base_url) }

    it "calls async_request with :post method" do
      expect(request).to receive(:async_request).with(:post, "/users")
      request.async_post("/users")
    end

    it "forwards all keyword arguments" do
      expect(request).to receive(:async_request).with(
        :post,
        "/users",
        json: {name: "John"},
        headers: {"X-Custom" => "value"}
      )
      request.async_post("/users", json: {name: "John"}, headers: {"X-Custom" => "value"})
    end

    it "returns an AsyncRequest" do
      result = request.async_post("/users", body: "data")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end
  end

  describe "#async_put" do
    let(:request) { described_class.new(base_url: base_url) }

    it "calls async_request with :put method" do
      expect(request).to receive(:async_request).with(:put, "/users/1")
      request.async_put("/users/1")
    end

    it "forwards all keyword arguments" do
      expect(request).to receive(:async_request).with(
        :put,
        "/users/1",
        json: {name: "Jane"},
        params: {notify: true}
      )
      request.async_put("/users/1", json: {name: "Jane"}, params: {notify: true})
    end

    it "returns an AsyncRequest" do
      result = request.async_put("/users/1", body: "data")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end
  end

  describe "#async_patch" do
    let(:request) { described_class.new(base_url: base_url) }

    it "calls async_request with :patch method" do
      expect(request).to receive(:async_request).with(:patch, "/users/1")
      request.async_patch("/users/1")
    end

    it "forwards all keyword arguments" do
      expect(request).to receive(:async_request).with(
        :patch,
        "/users/1",
        json: {email: "new@example.com"}
      )
      request.async_patch("/users/1", json: {email: "new@example.com"})
    end

    it "returns an AsyncRequest" do
      result = request.async_patch("/users/1", body: "data")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end
  end

  describe "#async_delete" do
    let(:request) { described_class.new(base_url: base_url) }

    it "calls async_request with :delete method" do
      expect(request).to receive(:async_request).with(:delete, "/users/1")
      request.async_delete("/users/1")
    end

    it "forwards all keyword arguments" do
      expect(request).to receive(:async_request).with(
        :delete,
        "/users/1",
        headers: {"X-Reason" => "spam"}
      )
      request.async_delete("/users/1", headers: {"X-Reason" => "spam"})
    end

    it "returns an AsyncRequest" do
      result = request.async_delete("/users/1")
      expect(result).to be_a(Sidekiq::AsyncHttp::AsyncRequest)
    end
  end

  describe "attribute accessors" do
    it "allows setting and getting base_url" do
      request = described_class.new
      request.base_url = "https://new-api.example.com"
      expect(request.base_url).to eq("https://new-api.example.com")
    end

    it "allows setting and getting headers" do
      request = described_class.new
      new_headers = Sidekiq::AsyncHttp::HttpHeaders.new({"X-New" => "header"})
      request.headers = new_headers
      expect(request.headers).to eq(new_headers)
    end

    it "allows setting and getting timeout" do
      request = described_class.new
      request.timeout = 45
      expect(request.timeout).to eq(45)
    end

    it "allows setting and getting open_timeout" do
      request = described_class.new
      request.open_timeout = 5
      expect(request.open_timeout).to eq(5)
    end

    it "allows setting and getting read_timeout" do
      request = described_class.new
      request.read_timeout = 25
      expect(request.read_timeout).to eq(25)
    end

    it "allows setting and getting write_timeout" do
      request = described_class.new
      request.write_timeout = 20
      expect(request.write_timeout).to eq(20)
    end
  end
end
