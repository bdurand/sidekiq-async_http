# frozen_string_literal: true

require "concurrent"

module Sidekiq
  module AsyncHttp
    # Manages the lifecycle state of the Processor.
    #
    # Handles state transitions and provides predicates for checking the current state.
    # Thread-safe state management using Concurrent::AtomicReference.
    #
    # @note State transition methods (start!, stop!, drain!) use a read-then-write pattern.
    #   Callers must provide external synchronization (e.g., via Mutex) when calling
    #   these methods from multiple threads to prevent race conditions.
    class LifecycleManager
      include TimeHelper

      # Valid processor states
      STATES = %i[stopped starting running draining stopping].freeze

      # Polling interval during wait operations
      POLL_INTERVAL = 0.001

      # Initialize the lifecycle manager.
      #
      # @return [void]
      def initialize
        @state = Concurrent::AtomicReference.new(:stopped)
        @shutdown_barrier = Concurrent::Event.new
        @reactor_ready = Concurrent::Event.new
      end

      # Get the current state.
      #
      # @return [Symbol] the current state
      def state
        @state.get
      end

      # Check if processor is starting.
      #
      # @return [Boolean] true if starting
      def starting?
        state == :starting
      end

      # Check if processor is running.
      #
      # @return [Boolean] true if running
      def running?
        state == :running
      end

      # Check if processor is stopped.
      #
      # @return [Boolean] true if stopped
      def stopped?
        state == :stopped
      end

      # Check if processor is draining.
      #
      # @return [Boolean] true if draining
      def draining?
        state == :draining
      end

      # Check if processor is stopping.
      #
      # @return [Boolean] true if stopping
      def stopping?
        state == :stopping
      end

      # Transition to starting state.
      #
      # @return [Boolean] true if transition was successful
      def start!
        return false if starting? || running? || stopping?

        @state.set(:starting)
        @shutdown_barrier.reset
        @reactor_ready.reset
        true
      end

      # Transition to running state.
      #
      # @return [void]
      def running!
        @state.set(:running)
      end

      # Transition to draining state.
      #
      # @return [Boolean] true if transition was successful
      def drain!
        return false unless running?

        @state.set(:draining)
        true
      end

      # Transition to stopping state.
      #
      # @return [Boolean] true if transition was successful
      def stop!
        return false if stopped? || stopping? || starting?

        @state.set(:stopping)
        @shutdown_barrier.set
        true
      end

      # Transition to stopped state.
      #
      # @return [void]
      def stopped!
        @state.set(:stopped)
      end

      # Signal that the reactor is ready.
      #
      # @return [void]
      def reactor_ready!
        @reactor_ready.set
      end

      # Wait for the reactor to be ready.
      #
      # @return [void]
      def wait_for_reactor
        @reactor_ready.wait
      end

      # Check if shutdown has been signaled.
      #
      # @return [Boolean] true if shutdown is signaled
      def shutdown_signaled?
        @shutdown_barrier.set?
      end

      # Wait for running state.
      #
      # @param timeout [Numeric] maximum time to wait in seconds
      # @return [Boolean] true if running, false if timeout reached
      def wait_for_running(timeout: 5)
        deadline = monotonic_time + timeout
        while monotonic_time <= deadline
          return true if running?

          sleep(POLL_INTERVAL)
        end
        false
      end

      # Wait for idle state.
      #
      # @param timeout [Numeric] maximum time to wait in seconds
      # @yield Block that returns true if idle
      # @return [Boolean] true if idle, false if timeout reached
      def wait_for_idle(timeout: 1)
        deadline = monotonic_time + timeout
        while monotonic_time <= deadline
          return true if yield

          sleep(POLL_INTERVAL)
        end
        false
      end

      # Wait for processing to start.
      #
      # @param timeout [Numeric] maximum time to wait in seconds
      # @yield Block that returns true if processing
      # @return [Boolean] true if processing, false if timeout reached
      def wait_for_processing(timeout: 1)
        deadline = monotonic_time + timeout
        while monotonic_time <= deadline
          return true if yield

          sleep(POLL_INTERVAL)
        end
        false
      end
    end
  end
end
