# frozen_string_literal: true

# Suppress experimental feature warnings (IO::Buffer used by async gems)
Warning[:experimental] = false

# SimpleCov must be started before requiring the lib
require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end

require "bundler/setup"

require "webmock/rspec"
require "async/rspec"
require "sidekiq/testing"

require_relative "../lib/sidekiq-async_http"

# Disable all real HTTP connections
WebMock.disable_net_connect!

# Use fake mode for Sidekiq during tests
Sidekiq::Testing.fake!

# Disable Sidekiq logging during tests
Sidekiq.logger.level = Logger::FATAL

# Simple test request class that matches what the processor expects
class TestRequest
  attr_accessor :id, :method, :url, :headers, :body, :timeout, :success_worker_class, :error_worker_class, :job_args, :original_worker_class, :original_args

  def initialize(id: "req-123", method: :get, url: "https://api.example.com/users", headers: {}, body: nil, timeout: 30, success_worker_class: nil, error_worker_class: nil, job_args: [], original_worker_class: nil, original_args: [])
    @id = id
    @method = method
    @url = url
    @headers = headers
    @body = body
    @timeout = timeout
    @success_worker_class = success_worker_class
    @error_worker_class = error_worker_class
    @job_args = job_args
    @original_worker_class = original_worker_class || "TestWorker"
    @original_args = original_args.any? ? original_args : job_args
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  # Include Async::RSpec::Reactor for async tests
  config.include Async::RSpec::Reactor

  # Reset SidekiqAsyncHttp state between tests
  config.before do
    # Clear Sidekiq queues
    Sidekiq::Worker.clear_all

    # Reset Sidekiq::AsyncHttp if it has been initialized
    if defined?(Sidekiq::AsyncHttp) && Sidekiq::AsyncHttp.instance_variable_get(:@processor)
      Sidekiq::AsyncHttp.processor&.shutdown
    end
  end

  config.after do
    # Ensure processor is stopped after each test
    if defined?(Sidekiq::AsyncHttp) && Sidekiq::AsyncHttp.instance_variable_get(:@processor)
      Sidekiq::AsyncHttp.processor&.shutdown
    end
  end
end
