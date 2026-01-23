# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::ResponseReader do
  let(:config) { Sidekiq::AsyncHttp::Configuration.new }
  let(:response_reader) { described_class.new(config) }

  describe "#read_body" do
    let(:body_double) { instance_double(Protocol::HTTP::Body::Buffered) }
    let(:async_response) { instance_double("Async::HTTP::Protocol::Response", body: body_double) }
    let(:headers_hash) { {} }

    context "when response has no body" do
      let(:async_response) { instance_double("Async::HTTP::Protocol::Response", body: nil) }

      it "returns nil" do
        expect(response_reader.read_body(async_response, headers_hash)).to be_nil
      end
    end

    context "when response has a body" do
      before do
        allow(body_double).to receive(:each).and_yield("Hello, ").and_yield("World!")
      end

      it "reads and joins all chunks" do
        result = response_reader.read_body(async_response, headers_hash)
        expect(result).to eq("Hello, World!")
      end
    end

    context "when content-length exceeds max_response_size" do
      let(:headers_hash) { {"content-length" => "10000001"} }

      before do
        config.max_response_size = 10_000_000
      end

      it "raises ResponseTooLargeError" do
        expect {
          response_reader.read_body(async_response, headers_hash)
        }.to raise_error(Sidekiq::AsyncHttp::ResponseTooLargeError, /10000001 bytes.*exceeds maximum/)
      end
    end

    context "when content-length is within max_response_size" do
      let(:headers_hash) { {"content-length" => "13"} }

      before do
        config.max_response_size = 10_000_000
        allow(body_double).to receive(:each).and_yield("Hello, World!")
      end

      it "reads the body" do
        result = response_reader.read_body(async_response, headers_hash)
        expect(result).to eq("Hello, World!")
      end
    end

    context "when body exceeds max_response_size during reading" do
      before do
        config.max_response_size = 10
        allow(body_double).to receive(:each).and_yield("Hello, ").and_yield("World!")
      end

      it "raises ResponseTooLargeError" do
        expect {
          response_reader.read_body(async_response, headers_hash)
        }.to raise_error(Sidekiq::AsyncHttp::ResponseTooLargeError, /exceeded maximum allowed size/)
      end
    end

    context "when body is exactly at max_response_size" do
      before do
        config.max_response_size = 13
        allow(body_double).to receive(:each).and_yield("Hello, World!")
      end

      it "reads the body successfully" do
        result = response_reader.read_body(async_response, headers_hash)
        expect(result).to eq("Hello, World!")
      end
    end
  end

  describe "#build_response" do
    let(:request) do
      Sidekiq::AsyncHttp::Request.new(:post, "https://example.com/api")
    end

    let(:sidekiq_job) do
      {"class" => "TestWorker", "jid" => "abc123", "args" => []}
    end

    let(:task) do
      Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: sidekiq_job,
        completion_worker: "TestWorker"
      ).tap { |t|
        t.enqueued!
        t.started!
        t.completed!
      }
    end

    let(:response_data) do
      {
        status: 200,
        headers: {"content-type" => "application/json"},
        body: '{"success": true}',
        protocol: "HTTP/2"
      }
    end

    it "builds a Response object with all attributes" do
      response = response_reader.build_response(task, response_data)

      expect(response).to be_a(Sidekiq::AsyncHttp::Response)
      expect(response.status).to eq(200)
      expect(response.headers["content-type"]).to eq("application/json")
      expect(response.body).to eq('{"success": true}')
      expect(response.protocol).to eq("HTTP/2")
      expect(response.request_id).to eq(task.id)
      expect(response.url).to eq("https://example.com/api")
      expect(response.http_method).to eq(:post)
    end

    it "includes the task duration" do
      response = response_reader.build_response(task, response_data)

      expect(response.duration).to be_a(Float)
      expect(response.duration).to be >= 0
    end

    context "with different HTTP methods" do
      let(:request) do
        Sidekiq::AsyncHttp::Request.new(:delete, "https://example.com/resource")
      end

      it "preserves the HTTP method" do
        response = response_reader.build_response(task, response_data)
        expect(response.http_method).to eq(:delete)
      end
    end

    context "with nil body" do
      let(:response_data) do
        {
          status: 204,
          headers: {},
          body: nil,
          protocol: "HTTP/1.1"
        }
      end

      it "builds response with nil body" do
        response = response_reader.build_response(task, response_data)

        expect(response.status).to eq(204)
        expect(response.body).to be_nil
      end
    end
  end
end
