# frozen_string_literal: true

require "time"
require "socket"
require "singleton"

module Sidekiq
  module AsyncHttp
    # Stores processor statistics in Redis with automatic expiration.
    #
    # Tracks three types of stats:
    # 1. Hourly stats (30 days): requests, duration, errors, refused
    # 2. Running totals (30 days): requests, duration, errors, refused
    # 3. Per-process inflight counts (300 seconds): current inflight by host
    class Stats
      include Singleton

      # Redis key prefixes
      HOURLY_PREFIX = "sidekiq:async_http:hourly"
      TOTALS_KEY = "sidekiq:async_http:totals"
      INFLIGHT_PREFIX = "sidekiq:async_http:inflight"
      MAX_CONNECTIONS_PREFIX = "sidekiq:async_http:max_connections"

      # TTLs
      HOURLY_TTL = 30 * 24 * 60 * 60 # 30 days in seconds
      TOTALS_TTL = 30 * 24 * 60 * 60 # 30 days in seconds
      INFLIGHT_TTL = 300 # 5 minutes in seconds

      def initialize
        @hostname = ::Socket.gethostname.force_encoding("UTF-8").freeze
        @pid = ::Process.pid
      end

      # Record a completed request
      #
      # @param duration [Float] request duration in seconds
      # @return [void]
      def record_request(duration)
        hour_key = current_hour_key

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            # Increment hourly counters
            transaction.hincrby(hour_key, "requests", 1)
            transaction.hincrbyfloat(hour_key, "duration", duration.to_f)
            transaction.expire(hour_key, HOURLY_TTL)

            # Increment total counters
            transaction.hincrby(TOTALS_KEY, "requests", 1)
            transaction.hincrbyfloat(TOTALS_KEY, "duration", duration.to_f)
            transaction.expire(TOTALS_KEY, TOTALS_TTL)
          end
        end
      end

      # Record a request error
      #
      # @return [void]
      def record_error
        hour_key = current_hour_key

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            # Increment hourly error counter
            transaction.hincrby(hour_key, "errors", 1)
            transaction.expire(hour_key, HOURLY_TTL)

            # Increment total error counter
            transaction.hincrby(TOTALS_KEY, "errors", 1)
            transaction.expire(TOTALS_KEY, TOTALS_TTL)
          end
        end
      end

      # Record a refused request (max capacity reached)
      #
      # @return [void]
      def record_refused
        hour_key = current_hour_key

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            # Increment hourly refused counter
            transaction.hincrby(hour_key, "refused", 1)
            transaction.expire(hour_key, HOURLY_TTL)

            # Increment total refused counter
            transaction.hincrby(TOTALS_KEY, "refused", 1)
            transaction.expire(TOTALS_KEY, TOTALS_TTL)
          end
        end
      end

      # Update the inflight request count and max connections for this process
      #
      # @param count [Integer] current number of inflight requests
      # @param max_connections [Integer] maximum connections for this process
      # @return [void]
      def update_inflight(count, max_connections)
        inflight_key = "#{INFLIGHT_PREFIX}:#{@hostname}:#{@pid}"
        max_connections_key = "#{MAX_CONNECTIONS_PREFIX}:#{@hostname}:#{@pid}"

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            transaction.set(inflight_key, count, ex: INFLIGHT_TTL)
            transaction.set(max_connections_key, max_connections, ex: INFLIGHT_TTL)
          end
        end
      end

      # Get hourly stats for a specific hour
      #
      # @param time [Time] the time to get stats for (defaults to current hour)
      # @return [Hash] hash with requests, duration, errors, refused
      def get_hourly_stats(time = Time.now)
        hour_key = hour_key_for_time(time)

        stats = Sidekiq.redis do |redis|
          redis.hgetall(hour_key)
        end

        {
          "requests" => (stats["requests"] || 0).to_i,
          "duration" => (stats["duration"] || 0).to_f,
          "errors" => (stats["errors"] || 0).to_i,
          "refused" => (stats["refused"] || 0).to_i
        }
      end

      # Get running totals
      #
      # @return [Hash] hash with requests, duration, errors, refused
      def get_totals
        Sidekiq.redis do |redis|
          stats = redis.hgetall(TOTALS_KEY)
          {
            "requests" => (stats["requests"] || 0).to_i,
            "duration" => (stats["duration"] || 0).to_f,
            "errors" => (stats["errors"] || 0).to_i,
            "refused" => (stats["refused"] || 0).to_i
          }
        end
      end

      # Get all inflight counts across all processes
      #
      # @return [Hash] hash of "hostname:pid" => count
      def get_all_inflight
        Sidekiq.redis do |redis|
          keys = redis.keys("#{INFLIGHT_PREFIX}:*")
          result = {}
          keys.each do |key|
            # Extract hostname:pid from key
            identifier = key.sub("#{INFLIGHT_PREFIX}:", "")
            count = redis.get(key).to_i
            result[identifier] = count
          end
          result
        end
      end

      # Get the total max connections across all processes
      #
      # @return [Integer] sum of max connections from all active processes
      def get_total_max_connections
        Sidekiq.redis do |redis|
          keys = redis.keys("#{MAX_CONNECTIONS_PREFIX}:*")
          total = 0
          keys.each do |key|
            total += redis.get(key).to_i
          end
          total
        end
      end

      # Remove process-specific keys (called during processor shutdown)
      #
      # @return [void]
      def cleanup_process_keys
        inflight_key = "#{INFLIGHT_PREFIX}:#{@hostname}:#{@pid}"
        max_connections_key = "#{MAX_CONNECTIONS_PREFIX}:#{@hostname}:#{@pid}"

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            transaction.del(inflight_key)
            transaction.del(max_connections_key)
          end
        end
      end

      # Get total inflight count across all processes
      #
      # @return [Integer] total number of inflight requests
      def get_total_inflight
        get_all_inflight.values.sum
      end

      # Reset all stats (useful for testing)
      #
      # @return [void]
      def reset!
        Sidekiq.redis do |redis|
          # Delete all hourly keys
          hourly_keys = redis.keys("#{HOURLY_PREFIX}:*")
          redis.del(*hourly_keys) unless hourly_keys.empty?

          # Delete totals
          redis.del(TOTALS_KEY)

          # Delete all inflight keys
          inflight_keys = redis.keys("#{INFLIGHT_PREFIX}:*")
          redis.del(*inflight_keys) unless inflight_keys.empty?

          # Delete all max_connections keys
          max_connections_keys = redis.keys("#{MAX_CONNECTIONS_PREFIX}:*")
          redis.del(*max_connections_keys) unless max_connections_keys.empty?
        end
      end

      private

      # Get the Redis key for the current hour
      #
      # @return [String]
      def current_hour_key
        hour_key_for_time(Time.now)
      end

      # Get the Redis key for a specific hour
      #
      # @param time [Time]
      # @return [String]
      def hour_key_for_time(time)
        timestamp = time.utc.strftime("%Y%m%d%H")
        "#{HOURLY_PREFIX}:#{timestamp}"
      end
    end
  end
end
