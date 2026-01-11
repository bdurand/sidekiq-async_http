# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Capacity Limit Integration", :integration do
  include Async::RSpec::Reactor

  let(:config) do
    Sidekiq::AsyncHttp::Configuration.new.tap do |c|
      c.max_connections = 2 # Set low limit for testing
      c.default_request_timeout = 10
      c.http2_enabled = false # WEBrick only supports HTTP/1.1
    end
  end

  let!(:processor) { Sidekiq::AsyncHttp::Processor.new(config) }

  before do
    # Clear any pending Sidekiq jobs first
    Sidekiq::Queues.clear_all

    # Reset all worker call tracking
    TestWorkers::Worker.reset_calls!
    TestWorkers::SuccessWorker.reset_calls!
    TestWorkers::ErrorWorker.reset_calls!

    @test_server = nil

    # Disable WebMock completely for integration tests
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!

    Sidekiq::Testing.fake!
  end

  after do
    # Stop processor with minimal timeout
    processor.stop(timeout: 0) if processor.running?

    # Clean up test server
    cleanup_server(@test_server) if @test_server

    # Re-enable WebMock
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe "enforcing max_connections limit" do
    it "raises error when attempting to exceed capacity and allows enqueue after request completes" do
      # Start test HTTP server with configurable delays
      request_delays = {}
      @test_server = with_test_server do |s|
        s.on_request do |request|
          delay = request_delays[request.path] || 0.1
          sleep(delay)

          {
            status: 200,
            body: %{{"result":"completed","path":"#{request.path}"}},
            headers: {"Content-Type" => "application/json"}
          }
        end
      end

      # Start processor
      processor.start
      expect(processor.running?).to be true

      # Verify initial state
      expect(processor.metrics.in_flight_count).to eq(0)

      # Build client
      client = Sidekiq::AsyncHttp::Client.new(base_url: @test_server.url)

      # Configure delays: requests 1 and 2 are slow (1 second), request 3 is fast
      request_delays["/request-1"] = 1.0
      request_delays["/request-2"] = 1.0
      request_delays["/request-3"] = 0.1

      # Enqueue first long-running request
      request1 = client.async_get("/request-1")
      request_task1 = Sidekiq::AsyncHttp::RequestTask.new(
        request: request1,
        sidekiq_job: {
          "class" => "TestWorkers::Worker",
          "jid" => "jid-1",
          "args" => ["arg1"]
        },
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )
      processor.enqueue(request_task1)

      # Enqueue second long-running request
      request2 = client.async_get("/request-2")
      request_task2 = Sidekiq::AsyncHttp::RequestTask.new(
        request: request2,
        sidekiq_job: {
          "class" => "TestWorkers::Worker",
          "jid" => "jid-2",
          "args" => ["arg2"]
        },
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )
      processor.enqueue(request_task2)

      # Wait for both requests to start processing
      expect(processor.wait_for_processing(timeout: 2)).to be true

      # Give them a moment to be fully in-flight
      sleep(0.1)

      # Verify we're at capacity (2 in-flight)
      expect(processor.metrics.in_flight_count).to eq(2)

      # Attempt to enqueue third request - should raise error
      request3 = client.async_get("/request-3")
      request_task3 = Sidekiq::AsyncHttp::RequestTask.new(
        request: request3,
        sidekiq_job: {
          "class" => "TestWorkers::Worker",
          "jid" => "jid-3",
          "args" => ["arg3"]
        },
        success_worker: "TestWorkers::SuccessWorker",
        error_worker: "TestWorkers::ErrorWorker"
      )

      # Should raise error due to capacity limit
      expect {
        processor.enqueue(request_task3)
      }.to raise_error(RuntimeError, /at capacity/)

      # Verify still only 2 in-flight
      expect(processor.metrics.in_flight_count).to eq(2)

      # Wait for the first two requests to complete
      expect(processor.wait_for_idle(timeout: 3)).to be true

      # Verify both completed
      expect(processor.metrics.in_flight_count).to eq(0)

      # Now we should be able to enqueue the third request
      expect {
        processor.enqueue(request_task3)
      }.not_to raise_error

      # Wait for third request to complete
      expect(processor.wait_for_idle(timeout: 2)).to be true

      # Process all callbacks
      Sidekiq::Worker.drain_all

      # Verify all 3 requests completed successfully
      expect(TestWorkers::SuccessWorker.calls.size).to eq(3)
      expect(TestWorkers::ErrorWorker.calls.size).to eq(0)

      # Verify no errors in metrics
      expect(processor.metrics.error_count).to eq(0)

      # Verify processor is still running
      expect(processor.running?).to be true
    end
  end
end
