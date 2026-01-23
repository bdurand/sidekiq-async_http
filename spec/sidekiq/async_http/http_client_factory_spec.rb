# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::HttpClientFactory do
  let(:config) { Sidekiq::AsyncHttp.configuration }
  let(:factory) { described_class.new(config) }

  let(:request) do
    Sidekiq::AsyncHttp::Request.new(
      :get,
      "https://api.example.com/users",
      headers: {"Accept" => "application/json"},
      timeout: 30,
      connect_timeout: 5.0
    )
  end

  describe ".new" do
    it "stores the configuration" do
      expect(factory.config).to eq(config)
    end
  end

  describe "#build" do
    it "returns a wrapped HTTP client" do
      client = factory.build(request)
      expect(client).to be_a(Protocol::HTTP::AcceptEncoding)
    end
  end

  describe "#create_endpoint" do
    it "creates an endpoint with the request URL" do
      endpoint = factory.create_endpoint(request)
      expect(endpoint.url.to_s).to eq("https://api.example.com/users")
    end

    it "passes connect_timeout to Endpoint.parse" do
      expect(Async::HTTP::Endpoint).to receive(:parse).with(
        request.url,
        hash_including(connect_timeout: 5.0)
      ).and_call_original

      factory.create_endpoint(request)
    end

    it "passes idle_timeout from configuration to Endpoint.parse" do
      expect(Async::HTTP::Endpoint).to receive(:parse).with(
        request.url,
        hash_including(idle_timeout: config.idle_connection_timeout)
      ).and_call_original

      factory.create_endpoint(request)
    end

    it "handles nil connect_timeout" do
      request_without_timeout = Sidekiq::AsyncHttp::Request.new(
        :get,
        "https://api.example.com/users"
      )

      expect(Async::HTTP::Endpoint).to receive(:parse).with(
        request_without_timeout.url,
        hash_including(connect_timeout: nil)
      ).and_call_original

      factory.create_endpoint(request_without_timeout)
    end
  end

  describe "#create_client" do
    it "creates an Async::HTTP::Client from endpoint" do
      endpoint = factory.create_endpoint(request)
      client = factory.create_client(endpoint)
      expect(client).to be_a(Async::HTTP::Client)
    end
  end

  describe "#wrap_client" do
    it "wraps client with AcceptEncoding middleware" do
      endpoint = factory.create_endpoint(request)
      client = factory.create_client(endpoint)
      wrapped = factory.wrap_client(client)
      expect(wrapped).to be_a(Protocol::HTTP::AcceptEncoding)
    end
  end
end
