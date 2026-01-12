# frozen_string_literal: true

require "concurrent"

module Sidekiq
  module AsyncHttp
    # Thread-safe metrics collection for async HTTP requests
    class Metrics
      attr_reader :stats

      def initialize(stats: nil)
        @total_requests = Concurrent::AtomicFixnum.new(0)
        @error_count = Concurrent::AtomicFixnum.new(0)
        @refused_count = Concurrent::AtomicFixnum.new(0)
        @total_duration = Concurrent::AtomicReference.new(0.0)
        @in_flight_requests = Concurrent::AtomicFixnum.new(0)
        @errors_by_type = Concurrent::Map.new
        @stats = stats
        @last_inflight_update = Concurrent::AtomicReference.new(Time.now.to_f)
      end

      # Record the start of a request
      #
      # @param task [RequestTask] the request task being started
      # @return [void]
      def record_request_start(request)
        @in_flight_requests.increment
        update_inflight_stats
      end

      # Record the completion of a request
      #
      # @param task [RequestTask] the completed request task
      # @param duration [Float] request duration in seconds
      # @return [void]
      def record_request_complete(request, duration)
        @in_flight_requests.decrement
        @total_requests.increment

        if duration
          loop do
            current_total = @total_duration.get
            new_total = current_total + duration
            break if @total_duration.compare_and_set(current_total, new_total)
          end

          # Record in stats if available
          @stats&.record_request(duration)
        end

        update_inflight_stats
      end

      # Record an error
      #
      # @param task [RequestTask] the failed request task
      # @param error_type [Symbol] the error type (:timeout, :connection, :ssl, :protocol, :unknown)
      # @return [void]
      def record_error(request, error_type)
        @error_count.increment

        # Get or create atomic counter for this error type and increment it
        counter = @errors_by_type.compute_if_absent(error_type) do
          Concurrent::AtomicFixnum.new(0)
        end
        counter.increment

        # Record in stats if available
        @stats&.record_error
      end

      # Record a refused request (max capacity reached)
      #
      # @return [void]
      def record_refused
        @refused_count.increment
        @stats&.record_refused
      end

      # Get the number of in-flight requests
      # @return [Integer]
      def in_flight_count
        @in_flight_requests.value
      end

      # Get total number of requests processed
      # @return [Integer]
      def total_requests
        @total_requests.value
      end

      # Get average request duration
      # @return [Float] average duration in seconds, or 0 if no requests
      def average_duration
        total = total_requests
        return 0.0 if total.zero?

        @total_duration.get / total.to_f
      end

      # Get total error count
      # @return [Integer]
      def error_count
        @error_count.value
      end

      # Get errors grouped by type
      # @return [Hash<Symbol, Integer>] frozen hash of error type to count
      def errors_by_type
        result = {}
        @errors_by_type.each_pair do |type, count|
          result[type] = count.value
        end
        result.freeze
      end

      # Get a snapshot of all metrics
      # @return [Hash] hash with all metric values
      def to_h
        {
          "in_flight_count" => in_flight_count,
          "total_requests" => total_requests,
          "average_duration" => average_duration,
          "error_count" => error_count,
          "errors_by_type" => errors_by_type,
          "refused_count" => @refused_count.value
        }
      end

      # Reset all metrics (useful for testing)
      #
      # @return [void]
      def reset!
        @total_requests = Concurrent::AtomicFixnum.new(0)
        @error_count = Concurrent::AtomicFixnum.new(0)
        @total_duration = Concurrent::AtomicReference.new(0.0)
        @in_flight_requests = Concurrent::AtomicFixnum.new(0)
        @errors_by_type = Concurrent::Map.new
        @refused_count = Concurrent::AtomicFixnum.new(0)
        @last_inflight_update = Concurrent::AtomicReference.new(Time.now.to_f)
        @stats&.reset!
      end

      private

      # Update inflight stats (throttled to avoid excessive Redis calls)
      # Updates every 10 seconds
      #
      # @return [void]
      def update_inflight_stats
        return unless @stats

        now = Time.now.to_f
        last_update = @last_inflight_update.get

        # Only update every 10 seconds
        if now - last_update >= 10
          if @last_inflight_update.compare_and_set(last_update, now)
            count = in_flight_count
            @stats.update_inflight(count)
          end
        end
      end
    end
  end
end
