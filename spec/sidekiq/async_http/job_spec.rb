# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::Job do
  describe "including Sidekiq::Job" do
    let(:worker_class) do
      Class.new do
        include Sidekiq::AsyncHttp::Job
      end
    end

    it "includes Sidekiq::Job in the including class" do
      expect(worker_class.included_modules).to include(Sidekiq::Job)
    end
  end

  describe ".callback" do
    let(:worker_class) do
      Class.new do
        include Sidekiq::AsyncHttp::Job

        callback do
          def on_complete(response)
            # Handle completion
          end

          def on_error(error)
            # Handle error
          end
        end
      end
    end

    it "sets the callback_service_class" do
      expect(worker_class.callback_service_class).to eq(worker_class::AsyncHttpCallback)
    end

    it "defines an AsyncHttpCallback class with required methods" do
      callback_class = worker_class::AsyncHttpCallback
      expect(callback_class.method_defined?(:on_complete)).to be true
      expect(callback_class.method_defined?(:on_error)).to be true
    end

    it "callback class has on_complete method" do
      callback_class = worker_class::AsyncHttpCallback
      callback = callback_class.new
      expect(callback).to respond_to(:on_complete)
    end

    it "callback class has on_error method" do
      callback_class = worker_class::AsyncHttpCallback
      callback = callback_class.new
      expect(callback).to respond_to(:on_error)
    end
  end

  describe ".callback_service=" do
    let(:external_callback) do
      Class.new do
        def on_complete(response)
        end

        def on_error(error)
        end
      end
    end

    let(:worker_class) do
      callback = external_callback
      Class.new do
        include Sidekiq::AsyncHttp::Job

        self.callback_service = callback
      end
    end

    it "sets the callback_service_class to the external class" do
      expect(worker_class.callback_service_class).to eq(external_callback)
    end

    it "raises error if class does not have required methods" do
      invalid_class = Class.new

      expect do
        Class.new do
          include Sidekiq::AsyncHttp::Job

          self.callback_service = invalid_class
        end
      end.to raise_error(ArgumentError, /must define #on_complete instance method/)
    end
  end

  describe ".async_http_client" do
    it "can setup HTTP request defaults at the class level" do
      worker = TestWorkerWithClient.new
      expect(worker.async_http_client.base_url).to eq("https://example.org")
      expect(worker.async_http_client.headers["X-Custom-Header"]).to eq("Test")
    end
  end

  describe "request helper methods" do
    let(:worker_class) do
      Class.new do
        include Sidekiq::AsyncHttp::Job

        callback do
          def on_complete(response)
            TestCallback.record_completion(response)
          end

          def on_error(error)
            TestCallback.record_error(error)
          end
        end
      end
    end

    let(:request_tasks) { [] }

    let(:sidekiq_job) do
      {
        "class" => "TestWorker",
        "jid" => "test-jid-789",
        "args" => ["param1", 456, "action"]
      }
    end

    let(:worker_instance) { worker_class.new }

    around do |example|
      Sidekiq::AsyncHttp::Context.with_job(sidekiq_job) do
        example.run
      end
    end

    before do
      Sidekiq::AsyncHttp.start
      TestCallback.reset_calls!

      allow(Sidekiq::AsyncHttp.processor).to receive(:enqueue) do |task|
        request_tasks << task
      end
    end

    after do
      Sidekiq::AsyncHttp.stop
    end

    describe "#async_request" do
      it "enqueues an async HTTP request with given method" do
        worker_instance.async_request(:get, "https://api.example.com/data", timeout: 10)
        expect(request_tasks.size).to eq(1)
        task = request_tasks.first
        expect(task.request).to be_a(Sidekiq::AsyncHttp::Request)
        expect(task.request.http_method).to eq(:get)
        expect(task.request.url).to eq("https://api.example.com/data")
        expect(task.request.timeout).to eq(10)
      end

      it "uses the callback defined with the callback DSL" do
        worker_instance.async_request(:post, "https://api.example.com/data", body: "payload", timeout: 15)
        task = request_tasks.first
        expect(task.callback).to end_with("::AsyncHttpCallback")
      end

      it "passes callback_args to the request task" do
        worker_instance.async_request(
          :get,
          "https://api.example.com/data",
          callback_args: {custom: "callback", action: "args"}
        )

        task = request_tasks.first
        expect(task.callback_args).to eq({"custom" => "callback", "action" => "args"})
      end

      it "defaults callback_args to empty hash when not provided" do
        worker_instance.async_request(:get, "https://api.example.com/data")

        task = request_tasks.first
        expect(task.callback_args).to eq({})
      end

      it "uses global raise_error_responses config when not specified" do
        original_config = Sidekiq::AsyncHttp.configuration.raise_error_responses
        begin
          Sidekiq::AsyncHttp.configuration.raise_error_responses = true
          worker_instance.async_request(:get, "https://api.example.com/data")

          task = request_tasks.first
          expect(task.raise_error_responses).to eq(true)
        ensure
          Sidekiq::AsyncHttp.configuration.raise_error_responses = original_config
        end
      end

      it "allows explicit raise_error_responses to override global config" do
        original_config = Sidekiq::AsyncHttp.configuration.raise_error_responses
        begin
          Sidekiq::AsyncHttp.configuration.raise_error_responses = true
          worker_instance.async_request(:get, "https://api.example.com/data", raise_error_responses: false)

          task = request_tasks.first
          expect(task.raise_error_responses).to eq(false)
        ensure
          Sidekiq::AsyncHttp.configuration.raise_error_responses = original_config
        end
      end

      it "allows passing a custom callback" do
        worker_instance.async_request(
          :get,
          "https://api.example.com/data",
          callback: TestCallback
        )

        task = request_tasks.first
        expect(task.callback).to eq("TestCallback")
      end

      it "raises error if no callback is configured" do
        no_callback_worker = Class.new do
          include Sidekiq::AsyncHttp::Job
        end

        worker = no_callback_worker.new

        expect do
          Sidekiq::AsyncHttp::Context.with_job(sidekiq_job) do
            worker.async_request(:get, "https://api.example.com/data")
          end
        end.to raise_error(ArgumentError, /No callback service configured/)
      end
    end

    describe "#async_get" do
      it "calls async_request with GET method" do
        expect(worker_instance).to receive(:async_request).with(:get, "https://api.example.com/data", timeout: 5)
        worker_instance.async_get("https://api.example.com/data", timeout: 5)
      end
    end

    describe "#async_get!" do
      it "calls async_request with GET method and raise_error_responses: true" do
        expect(worker_instance).to receive(:async_request).with(:get, "https://api.example.com/data",
          raise_error_responses: true)
        worker_instance.async_get!("https://api.example.com/data")
      end
    end

    describe "#async_post" do
      it "calls async_request with POST method" do
        expect(worker_instance).to receive(:async_request).with(:post, "https://api.example.com/data", body: "payload",
          timeout: 15)
        worker_instance.async_post("https://api.example.com/data", body: "payload", timeout: 15)
      end
    end

    describe "#async_put" do
      it "calls async_request with PUT method" do
        expect(worker_instance).to receive(:async_request).with(:put, "https://api.example.com/data/1",
          json: {name: "test"}, timeout: 20)
        worker_instance.async_put("https://api.example.com/data/1", json: {name: "test"}, timeout: 20)
      end
    end

    describe "#async_patch" do
      it "calls async_request with PATCH method" do
        expect(worker_instance).to receive(:async_request).with(:patch, "https://api.example.com/data/1",
          body: "update", timeout: 25)
        worker_instance.async_patch("https://api.example.com/data/1", body: "update", timeout: 25)
      end
    end

    describe "#async_delete" do
      it "calls async_request with DELETE method" do
        expect(worker_instance).to receive(:async_request).with(:delete, "https://api.example.com/data/1", timeout: 30)
        worker_instance.async_delete("https://api.example.com/data/1", timeout: 30)
      end
    end
  end

  context "with an ActiveJob class" do
    let(:worker_class) do
      Class.new(ActiveJob::Base) do
        include Sidekiq::AsyncHttp::Job

        callback do
          def on_complete(response)
          end

          def on_error(error)
          end
        end
      end
    end

    before do
      active_job = Module.new
      active_job_base = Class.new do
        @queue_adapter_name = :sidekiq

        class << self
          attr_writer :queue_adapter_name

          def queue_adapter_name
            @queue_adapter_name&.to_s || superclass.queue_adapter_name
          end
        end
      end

      stub_const("ActiveJob", active_job)
      stub_const("ActiveJob::Base", active_job_base)
    end

    it "supports asynchronous requests if queue adapter is sidekiq" do
      ActiveJob::Base.queue_adapter_name = :sidekiq
      worker = worker_class.new
      expect(worker).to be_a(ActiveJob::Base)
      expect(worker.class.asynchronous_http_requests_supported?).to be true
    end

    it "does not support asynchronous requests if queue adapter is not sidekiq" do
      ActiveJob::Base.queue_adapter_name = :async
      worker = worker_class.new
      expect(worker).to be_a(ActiveJob::Base)
      expect(worker.class.asynchronous_http_requests_supported?).to be false
      expect do
        worker.async_get("https://api.example.com/data")
      end.to raise_error(/Asynchronous HTTP requests are not supported/)
    end

    it "defaults callback_args to empty hash for ActiveJob" do
      sidekiq_job = {
        "class" => "TestActiveJobWorker",
        "jid" => "activejob-jid-123",
        "args" => [
          {
            "arguments" => ["arg1", 789, "action2"],
            "job_id" => "job-456",
            "queue_name" => "default"
          }
        ]
      }

      worker_instance = worker_class.new

      Sidekiq::AsyncHttp.start

      captured_task = nil
      Sidekiq::AsyncHttp::Context.with_job(sidekiq_job) do
        allow(Sidekiq::AsyncHttp.processor).to receive(:enqueue) do |task|
          captured_task = task
        end

        worker_instance.async_request(:get, "https://api.example.com/data")
      end

      expect(captured_task.callback_args).to eq({})
    end
  end
end
