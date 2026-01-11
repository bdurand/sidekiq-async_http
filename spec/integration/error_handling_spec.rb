# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Error Handling Integration", :integration do
  include Async::RSpec::Reactor

  let(:config) do
    Sidekiq::AsyncHttp::Configuration.new.tap do |c|
      c.max_connections = 10
      c.default_request_timeout = 5
      c.http2_enabled = false # WEBrick only supports HTTP/1.1
    end
  end

  let(:processor) { Sidekiq::AsyncHttp::Processor.new(config) }

  before do
    TestWorkers::Worker.reset_calls!
    TestWorkers::SuccessWorker.reset_calls!
    TestWorkers::ErrorWorker.reset_calls!
    @test_server = nil

    # Disable WebMock completely for integration tests
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  after do
    processor.stop(timeout: 1) if processor.running?
    cleanup_server(@test_server) if @test_server

    # Re-enable WebMock
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe "timeout errors" do
    it "calls error worker with timeout error when request exceeds timeout" do
      # Start server with delay longer than timeout
      @test_server = with_test_server do |s|
        s.on_request do |request|
          sleep 2 # Delay longer than the request timeout
          {status: 200, body: "too late"}
        end
      end

      processor.start

      # Make request with short timeout
      client = Sidekiq::AsyncHttp::Client.new(base_url: @test_server.url, timeout: 0.5)
      request = client.async_get("/delayed")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "timeout-test", "args" => ["timeout_arg"]},
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 3)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # Verify error worker was called
      expect(TestWorkers::ErrorWorker.calls.size).to eq(1)
      expect(TestWorkers::SuccessWorker.calls.size).to eq(0)

      error, *original_args = TestWorkers::ErrorWorker.calls.first
      expect(error).to be_a(Sidekiq::AsyncHttp::Error)
      expect(error.error_type).to eq(:timeout)
      expect(error.class_name).to match(/Timeout/)
      expect(original_args).to eq(["timeout_arg"])
    end
  end

  describe "connection errors" do
    it "calls error worker with connection error when server is not listening" do
      processor.start

      # Make request to a port that's not listening
      client = Sidekiq::AsyncHttp::Client.new(base_url: "http://127.0.0.1:9999")
      request = client.async_get("/nowhere")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "conn-test", "args" => ["connection_arg"]},
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 2)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # Verify error worker was called
      expect(TestWorkers::ErrorWorker.calls.size).to eq(1)
      expect(TestWorkers::SuccessWorker.calls.size).to eq(0)

      error, *original_args = TestWorkers::ErrorWorker.calls.first
      expect(error).to be_a(Sidekiq::AsyncHttp::Error)
      expect(error.error_type).to eq(:connection)
      expect(error.class_name).to match(/Errno::E/)
      expect(error.message).to match(/refused|reset|connection/i)
      expect(original_args).to eq(["connection_arg"])
    end
  end

  describe "SSL errors" do
    it "calls error worker with ssl error for SSL issues" do
      processor.start

      # Try to make HTTPS request to HTTP server
      @test_server = with_test_server do |s|
        s.on_request do |request|
          {status: 200, body: "ok"}
        end
      end

      # Use https:// scheme with HTTP-only server
      url = @test_server.url.sub("http://", "https://")
      client = Sidekiq::AsyncHttp::Client.new(base_url: url)
      request = client.async_get("/test")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "ssl-test", "args" => ["ssl_arg"]},
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 2)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # Verify error worker was called
      expect(TestWorkers::ErrorWorker.calls.size).to eq(1)
      expect(TestWorkers::SuccessWorker.calls.size).to eq(0)

      error, *original_args = TestWorkers::ErrorWorker.calls.first
      expect(error).to be_a(Sidekiq::AsyncHttp::Error)
      expect(error.error_type).to eq(:ssl)
      expect(original_args).to eq(["ssl_arg"])
    end
  end

  describe "HTTP error responses" do
    it "calls success worker for 4xx responses (they are valid HTTP responses)" do
      @test_server = with_test_server do |s|
        s.on_request do |request|
          {status: 404, body: "Not Found"}
        end
      end

      processor.start

      client = Sidekiq::AsyncHttp::Client.new(base_url: @test_server.url)
      request = client.async_get("/missing")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "404-test", "args" => ["missing"]},
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 2)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # 404 is a valid HTTP response, so success worker is called
      expect(TestWorkers::SuccessWorker.calls.size).to eq(1)
      expect(TestWorkers::ErrorWorker.calls.size).to eq(0)

      response, *args = TestWorkers::SuccessWorker.calls.first
      expect(response.status).to eq(404)
      expect(response.body).to eq("Not Found")
      expect(response.client_error?).to be true
      expect(args).to eq(["missing"])
    end

    it "calls success worker for 5xx responses (they are valid HTTP responses)" do
      @test_server = with_test_server do |s|
        s.on_request do |request|
          {status: 503, body: "Service Unavailable"}
        end
      end

      processor.start

      client = Sidekiq::AsyncHttp::Client.new(base_url: @test_server.url)
      request = client.async_get("/unavailable")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "503-test", "args" => ["unavailable"]},
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 2)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # 503 is a valid HTTP response, so success worker is called
      expect(TestWorkers::SuccessWorker.calls.size).to eq(1)
      expect(TestWorkers::ErrorWorker.calls.size).to eq(0)

      response, *args = TestWorkers::SuccessWorker.calls.first
      expect(response.status).to eq(503)
      expect(response.body).to eq("Service Unavailable")
      expect(response.server_error?).to be true
      expect(args).to eq(["unavailable"])
    end
  end

  describe "error worker not provided" do
    it "logs error and does not crash when error_worker is nil" do
      processor.start

      # Make request to non-existent server without error_worker
      client = Sidekiq::AsyncHttp::Client.new(base_url: "http://127.0.0.1:9998")
      request = client.async_get("/nowhere")

      request_task = Sidekiq::AsyncHttp::RequestTask.new(
        request: request,
        sidekiq_job: {"class" => "TestWorkers::Worker", "jid" => "no-error-worker", "args" => ["test"]},
        success_worker: "TestWorkers::SuccessWorker"
        # Note: no error_worker provided
      )

      processor.enqueue(request_task)
      processor.wait_for_idle(timeout: 2)

      # Process enqueued jobs
      Sidekiq::Worker.drain_all

      # Neither worker should be called (error was logged)
      expect(TestWorkers::SuccessWorker.calls.size).to eq(0)
      expect(TestWorkers::ErrorWorker.calls.size).to eq(0)

      # Verify metrics recorded the error
      expect(processor.metrics.error_count).to eq(1)
      expect(processor.metrics.errors_by_type[:connection]).to eq(1)
    end
  end
end
