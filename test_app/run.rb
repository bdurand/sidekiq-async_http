#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "sidekiq"
require "puma"
require_relative "../lib/sidekiq-async_http"

# Redis URL from environment or default to localhost
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
port = ENV.fetch("PORT", "9292").to_i

# Configure Sidekiq client
Sidekiq.configure_client do |config|
  config.redis = {url: redis_url}
end

# Load test workers
require_relative "workers"

# Configure Sidekiq::AsyncHttp processor
Sidekiq::AsyncHttp.configure do |config|
  config.max_connections = ENV.fetch("MAX_CONNECTIONS", "20").to_i
end

puts "=" * 80
puts "Sidekiq::AsyncHttp Test Application"
puts "=" * 80
puts "Processor max_connections: #{Sidekiq::AsyncHttp.configuration.max_connections}"
puts "Redis URL: #{redis_url}"
puts "Web UI: http://localhost:#{port}/sidekiq"
puts "=" * 80
puts ""

# Load the Rack app (Sidekiq Web UI)
require "rack"
app = Rack::Builder.parse_file(File.expand_path("config.ru", __dir__))

# Embed Sidekiq using configure_embed
sidekiq = Sidekiq.configure_embed do |config|
  config.redis = {url: redis_url}
  config.logger.level = Logger::INFO
  config.queues = %w[default]
  config.concurrency = 10
end

# Start Sidekiq in a background thread
sidekiq_thread = Thread.new do
  sidekiq.run
end

# Start Puma server
server = Puma::Server.new(app, nil, {min_threads: 0, max_threads: 24, log_writer: Puma::LogWriter.stdio})
server.add_tcp_listener("127.0.0.1", port)

# Shutdown handling - use a queue to avoid trap context issues
shutdown_queue = Queue.new

trap("INT") do
  shutdown_queue << true
end

trap("TERM") do
  shutdown_queue << true
end

# Monitor shutdown queue in a separate thread
Thread.new do
  shutdown_queue.pop # Wait for shutdown signal

  sidekiq.stop
  sidekiq_thread.join(10) # Wait up to 10 seconds for graceful shutdown
  server.stop(true)
end

server.run.join
