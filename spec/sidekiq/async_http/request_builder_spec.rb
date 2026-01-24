# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::RequestBuilder do
  let(:config) { Sidekiq::AsyncHttp.configuration }
  let(:builder) { described_class.new(config) }

  describe ".new" do
    it "stores the configuration" do
      expect(builder.config).to eq(config)
    end
  end

  describe "#build" do
    context "with a simple GET request" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com/users",
          headers: {"Accept" => "application/json"}
        )
      end

      it "returns an Async::HTTP::Protocol::Request" do
        http_request = builder.build(request)
        expect(http_request).to be_a(Async::HTTP::Protocol::Request)
      end

      it "sets the correct scheme" do
        http_request = builder.build(request)
        expect(http_request.scheme).to eq("https")
      end

      it "sets the correct authority" do
        http_request = builder.build(request)
        expect(http_request.authority).to eq("api.example.com")
      end

      it "sets the correct method" do
        http_request = builder.build(request)
        expect(http_request.method).to eq("GET")
      end

      it "sets the correct path" do
        http_request = builder.build(request)
        expect(http_request.path).to eq("/users")
      end

      it "includes request headers" do
        http_request = builder.build(request)
        accept_header = http_request.headers["accept"]
        # Protocol::HTTP::Headers may return array or string
        expect([accept_header].flatten.first).to eq("application/json")
      end

      it "adds default user-agent when not provided" do
        http_request = builder.build(request)
        expect(http_request.headers["user-agent"]).to eq("sidekiq-async_http")
      end

      it "has no body" do
        http_request = builder.build(request)
        expect(http_request.body).to be_nil
      end
    end

    context "with a POST request with body" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :post,
          "https://api.example.com/users",
          headers: {"Content-Type" => "application/json"},
          body: '{"name":"John"}'
        )
      end

      it "sets the correct method" do
        http_request = builder.build(request)
        expect(http_request.method).to eq("POST")
      end

      it "includes the body" do
        http_request = builder.build(request)
        expect(http_request.body).to be_a(Protocol::HTTP::Body::Buffered)
      end

      it "body contains the correct content" do
        http_request = builder.build(request)
        expect(http_request.body.join).to eq('{"name":"John"}')
      end
    end

    context "with custom user-agent header" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com/users",
          headers: {"user-agent" => "custom-agent/1.0"}
        )
      end

      it "preserves the custom user-agent" do
        http_request = builder.build(request)
        expect(http_request.headers["user-agent"]).to eq("custom-agent/1.0")
      end
    end

    context "with configured user-agent" do
      let(:custom_config) do
        Sidekiq::AsyncHttp::Configuration.new.tap do |c|
          c.user_agent = "configured-agent/2.0"
        end
      end
      let(:builder) { described_class.new(custom_config) }

      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com/users"
        )
      end

      it "uses the configured user-agent" do
        http_request = builder.build(request)
        expect(http_request.headers["user-agent"]).to eq("configured-agent/2.0")
      end
    end

    context "with URL containing query string" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com/users?page=1&limit=10"
        )
      end

      it "includes query string in path" do
        http_request = builder.build(request)
        expect(http_request.path).to eq("/users?page=1&limit=10")
      end
    end

    context "with URL containing port" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com:8443/users"
        )
      end

      it "includes port in authority" do
        http_request = builder.build(request)
        expect(http_request.authority).to eq("api.example.com:8443")
      end
    end

    context "with nil headers" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(
          :get,
          "https://api.example.com/users",
          headers: nil
        )
      end

      it "handles nil headers gracefully" do
        http_request = builder.build(request)
        expect(http_request.headers["user-agent"]).to eq("sidekiq-async_http")
      end
    end
  end
end
